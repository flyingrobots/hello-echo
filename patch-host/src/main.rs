// SPDX-License-Identifier: Apache-2.0
// © James Ross Ω FLYING•ROBOTS <https://github.com/flyingrobots>

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use echo_edict_canonical::{decode_canonical_cbor_v1, encode_canonical_cbor_v1, CanonicalValueV1};
use serde::Deserialize;
use serde_json::{json, Value};
use warp_core::causal_wal::{
    FilesystemWalStore, Lsn, PayloadCodecId, PayloadSchemaId, WalDurabilityMode, WalSegmentId,
    WalStorePort, WalTransactionId, WriterEpoch, WriterEpochId,
};
use warp_core::external_action::{
    claim_external_action, reconcile_external_action_settlement_retry,
    record_external_action_request, ExternalActionAdapterBindingV1, ExternalActionAdapterIdV1,
    ExternalActionAdapterRegistryV1, ExternalActionCoordinatorV1,
    ExternalActionSettlementCandidateV1, ExternalActionSettlementKindV1,
    ExternalActionTransactionContextV1, RecoveredExternalActionPostureV1,
};
use warp_core::external_action_adapter::{
    admit_edict_external_action_request_v1, AdmittedEdictExternalActionRequestV1,
    EdictExternalActionAdmissionErrorV1,
};
use warp_core::validated_workspace_patch::{
    encode_validated_workspace_patch_input_v1, validated_workspace_patch_authority_v1,
    validated_workspace_patch_basis_v1, ValidatedWorkspacePatchAdapterV1,
    ValidatedWorkspacePatchProfileV1, ValidatedWorkspacePatchReconcilerV1,
};
use warp_core::{Hash, WorldlineId};

const SEGMENT_ID: WalSegmentId = WalSegmentId::from_raw(1);
const MAX_FILE_BYTES_V1: u64 = 65_536;

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct RequestCase {
    worldline_byte: u8,
    intent: String,
    proposal: PatchProposal,
    observation: WorkspaceObservation,
    permitted_paths: Vec<String>,
    max_settlement_bytes: u64,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct PatchProposal {
    path: String,
    replacement_bytes_hex: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct WorkspaceObservation {
    path: String,
    bytes_hex: String,
}

struct Invocation {
    phase: String,
    request_file: PathBuf,
    wal_dir: PathBuf,
    core_file: PathBuf,
    target_ir_file: PathBuf,
    argument: Option<String>,
}

fn main() {
    match run() {
        Ok(()) => {}
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(2);
        }
    }
}

fn run() -> Result<(), String> {
    let invocation = parse_invocation()?;
    let request_bytes = fs::read(&invocation.request_file).map_err(|error| error.to_string())?;
    let request_case: RequestCase = match serde_json::from_slice(&request_bytes) {
        Ok(request_case) => request_case,
        Err(_) => {
            let commit_count = wal_commit_count(&invocation.wal_dir)?;
            print_json(&json!({
                "phase": invocation.phase,
                "obstruction": "requestRejected",
                "wal": {"commitCount": commit_count}
            }))?;
            std::process::exit(3);
        }
    };
    let core_bytes = fs::read(&invocation.core_file).map_err(|error| error.to_string())?;
    let target_ir_bytes =
        fs::read(&invocation.target_ir_file).map_err(|error| error.to_string())?;

    let application_input = match application_input(&request_case) {
        Ok(input) => input,
        Err(_) => {
            let commit_count = wal_commit_count(&invocation.wal_dir)?;
            print_json(&json!({
                "phase": invocation.phase,
                "obstruction": "requestRejected",
                "wal": {"commitCount": commit_count}
            }))?;
            std::process::exit(3);
        }
    };
    let admitted = match admit_edict_external_action_request_v1(
        WorldlineId::from_bytes([request_case.worldline_byte; 32]),
        &core_bytes,
        &target_ir_bytes,
        &request_case.intent,
        &application_input,
    ) {
        Ok(admitted) => admitted,
        Err(error) => {
            let obstruction = if is_compiler_artifact_rejection(&error) {
                "compilerArtifactRejected"
            } else {
                "requestRejected"
            };
            let commit_count = wal_commit_count(&invocation.wal_dir)?;
            print_json(&json!({
                "phase": invocation.phase,
                "obstruction": obstruction,
                "wal": {"commitCount": commit_count}
            }))?;
            std::process::exit(3);
        }
    };

    match invocation.phase.as_str() {
        "request" => request_phase(&invocation, &request_case, &admitted),
        "claim" => claim_phase(&invocation, &request_case, &admitted),
        "inspect" | "replay" => inspect_phase(&invocation, &request_case, &admitted),
        "apply" => apply_phase(&invocation, &request_case, &admitted),
        "reconcile" => reconcile_phase(&invocation, &request_case, &admitted),
        "retry" => retry_phase(&invocation, &request_case, &admitted),
        phase => Err(format!("unsupported phase: {phase}")),
    }
}

fn parse_invocation() -> Result<Invocation, String> {
    let mut args = env::args().skip(1);
    let invocation = Invocation {
        phase: args.next().ok_or_else(|| "missing phase".to_owned())?,
        request_file: args
            .next()
            .map(PathBuf::from)
            .ok_or_else(|| "missing request file".to_owned())?,
        wal_dir: args
            .next()
            .map(PathBuf::from)
            .ok_or_else(|| "missing WAL directory".to_owned())?,
        core_file: args
            .next()
            .map(PathBuf::from)
            .ok_or_else(|| "missing Core artifact".to_owned())?,
        target_ir_file: args
            .next()
            .map(PathBuf::from)
            .ok_or_else(|| "missing Target IR artifact".to_owned())?,
        argument: args.next(),
    };
    if args.next().is_some() {
        return Err("too many arguments".to_owned());
    }
    Ok(invocation)
}

fn application_input(request_case: &RequestCase) -> Result<Vec<u8>, String> {
    if request_case.proposal.path != request_case.observation.path {
        return Err("proposal path did not match the witnessed observation path".to_owned());
    }
    let before = decode_hex(&request_case.observation.bytes_hex)?;
    let replacement = decode_hex(&request_case.proposal.replacement_bytes_hex)?;
    let max_file_bytes =
        usize::try_from(MAX_FILE_BYTES_V1).map_err(|_| "file budget was not representable")?;
    if before.len() > max_file_bytes || replacement.len() > max_file_bytes {
        return Err("patch data exceeded the host file budget".to_owned());
    }
    let patch = encode_validated_workspace_patch_input_v1(
        request_case.proposal.path.clone(),
        blake3::hash(&before).into(),
        replacement,
    )
    .map_err(|error| format!("validated patch encoding failed: {error:?}"))?;
    let authority = validated_workspace_patch_authority_v1(
        request_case.permitted_paths.iter().map(String::as_str),
    );
    let basis = validated_workspace_patch_basis_v1(&request_case.proposal.path, &before);
    encode_canonical_cbor_v1(&canonical_map([
        ("patch", CanonicalValueV1::Bytes(patch)),
        ("authority", CanonicalValueV1::Bytes(authority.to_vec())),
        ("basis", CanonicalValueV1::Bytes(basis.to_vec())),
        (
            "maxSettlementBytes",
            CanonicalValueV1::Integer(i128::from(request_case.max_settlement_bytes)),
        ),
        ("maxAttempts", CanonicalValueV1::Integer(1)),
    ]))
    .map_err(|error| format!("application input encoding failed: {error:?}"))
}

fn is_compiler_artifact_rejection(error: &EdictExternalActionAdmissionErrorV1) -> bool {
    matches!(
        error,
        EdictExternalActionAdmissionErrorV1::Canonical(_)
            | EdictExternalActionAdmissionErrorV1::ArtifactShape
            | EdictExternalActionAdmissionErrorV1::RequestCardinality
            | EdictExternalActionAdmissionErrorV1::CallableStepsPresent
            | EdictExternalActionAdmissionErrorV1::MissingSemanticClosure
            | EdictExternalActionAdmissionErrorV1::CoreDigestMismatch
            | EdictExternalActionAdmissionErrorV1::TargetDerivationMismatch
            | EdictExternalActionAdmissionErrorV1::CapabilityClosureMismatch
            | EdictExternalActionAdmissionErrorV1::UnsupportedExpression
            | EdictExternalActionAdmissionErrorV1::InvalidDigest
    )
}

fn request_phase(
    invocation: &Invocation,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> Result<(), String> {
    if invocation.argument.is_some() {
        return Err("request does not accept workspace authority".to_owned());
    }
    let (mut store, writer_epoch) = open_write_store(&invocation.wal_dir)?;
    let mut coordinator = recover(&store)?;
    record_external_action_request(
        &mut store,
        &mut coordinator,
        transaction_context("request", admitted, writer_epoch.epoch_id),
        admitted.request(),
    )
    .map_err(|error| format!("request admission failed: {error:?}"))?;
    print_report(
        &invocation.phase,
        request_case,
        admitted,
        &store,
        &coordinator,
        Some(&writer_epoch),
    )
}

fn claim_phase(
    invocation: &Invocation,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> Result<(), String> {
    if invocation.argument.is_some() {
        return Err("claim does not accept workspace authority".to_owned());
    }
    let (mut store, writer_epoch) = open_write_store(&invocation.wal_dir)?;
    let mut coordinator = recover(&store)?;
    let request = admitted.request();
    let recorded = coordinator
        .recorded_request(request.request_id())
        .map_err(|error| format!("request recovery failed: {error:?}"))?;
    let profile = adapter_profile(admitted);
    let binding = ExternalActionAdapterBindingV1 {
        adapter_id: profile.adapter_id,
        operation_id: profile.operation_id,
        authority_scope_digest: profile.authority_scope_digest,
    };
    let registry = ExternalActionAdapterRegistryV1::new([binding]);
    let authorization = registry
        .authorize(&request, binding.adapter_id)
        .map_err(|error| format!("adapter authorization failed: {error:?}"))?;
    claim_external_action(
        &mut store,
        &mut coordinator,
        transaction_context("claim", admitted, writer_epoch.epoch_id),
        recorded,
        authorization,
        request.basis_digest,
        0,
        digest("hello-effect-patch:adapter-lease"),
    )
    .map_err(|error| format!("claim admission failed: {error:?}"))?;
    print_report(
        &invocation.phase,
        request_case,
        admitted,
        &store,
        &coordinator,
        Some(&writer_epoch),
    )
}

fn inspect_phase(
    invocation: &Invocation,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> Result<(), String> {
    if invocation.argument.is_some() {
        return Err(format!(
            "{} does not accept workspace authority",
            invocation.phase
        ));
    }
    let store = open_read_store(&invocation.wal_dir)?;
    let coordinator = recover(&store)?;
    // Read-only phases take no writer lease and acquire no epoch.
    print_report(
        &invocation.phase,
        request_case,
        admitted,
        &store,
        &coordinator,
        None,
    )
}

fn apply_phase(
    invocation: &Invocation,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> Result<(), String> {
    let workspace_root = invocation
        .argument
        .as_ref()
        .map(Path::new)
        .ok_or_else(|| "apply requires a workspace root".to_owned())?;
    let (mut store, writer_epoch) = open_write_store(&invocation.wal_dir)?;
    let mut coordinator = recover(&store)?;
    let grant = coordinator
        .claim_grant(admitted.request().request_id())
        .map_err(|error| format!("claim recovery failed: {error:?}"))?;
    let adapter = ValidatedWorkspacePatchAdapterV1::open(
        workspace_root,
        request_case.permitted_paths.clone(),
        adapter_profile(admitted),
    )
    .map_err(|error| format!("adapter open failed: {error:?}"))?;
    let candidate = adapter
        .apply(&grant, admitted)
        .map_err(|error| format!("validated patch application failed: {error:?}"))?;
    adapter
        .admit_settlement(
            &mut store,
            &mut coordinator,
            transaction_context("settlement", admitted, writer_epoch.epoch_id),
            admitted,
            grant,
            candidate,
        )
        .map_err(|error| format!("settlement admission failed: {error:?}"))?;
    print_report(
        &invocation.phase,
        request_case,
        admitted,
        &store,
        &coordinator,
        Some(&writer_epoch),
    )
}

fn reconcile_phase(
    invocation: &Invocation,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> Result<(), String> {
    let workspace_root = invocation
        .argument
        .as_ref()
        .map(Path::new)
        .ok_or_else(|| "reconcile requires a workspace root".to_owned())?;
    let (mut store, writer_epoch) = open_write_store(&invocation.wal_dir)?;
    let mut coordinator = recover(&store)?;
    let grant = coordinator
        .claim_grant(admitted.request().request_id())
        .map_err(|error| format!("claim recovery failed: {error:?}"))?;
    let reconciler = ValidatedWorkspacePatchReconcilerV1::open(
        workspace_root,
        request_case.permitted_paths.clone(),
        adapter_profile(admitted),
    )
    .map_err(|error| format!("reconciler open failed: {error:?}"))?;
    let candidate = reconciler
        .reconcile(&grant, admitted)
        .map_err(|error| format!("patch reconciliation failed: {error:?}"))?;
    reconciler
        .admit_settlement(
            &mut store,
            &mut coordinator,
            transaction_context("settlement", admitted, writer_epoch.epoch_id),
            admitted,
            grant,
            candidate,
        )
        .map_err(|error| format!("reconciled settlement admission failed: {error:?}"))?;
    print_report(
        &invocation.phase,
        request_case,
        admitted,
        &store,
        &coordinator,
        Some(&writer_epoch),
    )
}

fn retry_phase(
    invocation: &Invocation,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> Result<(), String> {
    let retry_mode = invocation
        .argument
        .as_deref()
        .ok_or_else(|| "retry requires exact or conflict-kind".to_owned())?;
    let store = open_read_store(&invocation.wal_dir)?;
    let coordinator = recover(&store)?;
    let commit_count_before = store.read_commits().len();
    let admitted_settlement = coordinator
        .admitted_settlement(admitted.request().request_id())
        .map_err(|error| format!("settlement recovery failed: {error:?}"))?;
    let settlement = admitted_settlement.settlement();
    let kind = match retry_mode {
        "exact" => settlement.kind,
        "conflict-kind" => conflicting_kind(settlement.kind),
        _ => return Err(format!("unsupported retry mode: {retry_mode}")),
    };
    let candidate = ExternalActionSettlementCandidateV1::new(
        settlement.request_id,
        settlement.attempt_id,
        settlement.adapter_id,
        kind,
        settlement.settlement_schema_digest,
        settlement.basis_digest,
        settlement.canonical_result_bytes.clone(),
        settlement.schema_admission_evidence_digest,
        settlement.external_evidence_digest,
    );
    match reconcile_external_action_settlement_retry(&coordinator, candidate) {
        Ok(reconciled) if retry_mode == "exact" => {
            let report = report(
                &invocation.phase,
                request_case,
                admitted,
                &store,
                &coordinator,
                None,
            )?;
            let mut report = report
                .as_object()
                .cloned()
                .ok_or_else(|| "report was not an object".to_owned())?;
            report.insert("retry".to_owned(), json!("idempotent"));
            report.insert(
                "retryCommitDigest".to_owned(),
                json!(hex(&reconciled.settlement_commit_digest())),
            );
            report.insert(
                "wal".to_owned(),
                json!({
                    "commitCountBefore": commit_count_before,
                    "commitCountAfter": store.read_commits().len()
                }),
            );
            print_json(&Value::Object(report))
        }
        Err(_) if retry_mode == "conflict-kind" => {
            let mut report = report(
                &invocation.phase,
                request_case,
                admitted,
                &store,
                &coordinator,
                None,
            )?
            .as_object()
            .cloned()
            .ok_or_else(|| "report was not an object".to_owned())?;
            report.insert("retry".to_owned(), json!("obstructed"));
            report.insert("obstruction".to_owned(), json!("conflictingSettlement"));
            report.insert(
                "wal".to_owned(),
                json!({
                    "commitCountBefore": commit_count_before,
                    "commitCountAfter": store.read_commits().len()
                }),
            );
            print_json(&Value::Object(report))?;
            std::process::exit(3);
        }
        Ok(_) => Err("conflicting settlement retry unexpectedly admitted".to_owned()),
        Err(error) => Err(format!("exact settlement retry failed: {error:?}")),
    }
}

fn print_report(
    phase: &str,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
    store: &FilesystemWalStore,
    coordinator: &ExternalActionCoordinatorV1,
    writer_epoch: Option<&WriterEpoch>,
) -> Result<(), String> {
    print_json(&report(
        phase,
        request_case,
        admitted,
        store,
        coordinator,
        writer_epoch,
    )?)
}

fn report(
    phase: &str,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
    store: &FilesystemWalStore,
    coordinator: &ExternalActionCoordinatorV1,
    writer_epoch: Option<&WriterEpoch>,
) -> Result<Value, String> {
    let request = admitted.request();
    let recovered = coordinator
        .observed_index()
        .get(request.request_id())
        .ok_or_else(|| "request absent from recovered index".to_owned())?;
    let commits = store.read_commits();
    let settlement = recovered
        .settlement
        .as_ref()
        .map(|settlement| {
            let patch = decode_patch_settlement(&settlement.canonical_result_bytes)?;
            let commit_digest = recovered
                .settlement_commit_digest
                .ok_or_else(|| "settlement commit digest absent".to_owned())?;
            Ok::<_, String>(json!({
                "kind": settlement_kind(settlement.kind),
                "attemptId": hex(&settlement.attempt_id.as_hash()),
                "basisDigest": hex(&settlement.basis_digest),
                "externalEvidenceDigest": hex(&settlement.external_evidence_digest),
                "schemaAdmissionEvidenceDigest": hex(
                    &settlement.schema_admission_evidence_digest,
                ),
                "commitDigest": hex(&commit_digest),
                "resultDigest": hex(&settlement.result_digest),
                "canonicalResultByteCount": settlement.canonical_result_bytes.len(),
                "patch": patch
            }))
        })
        .transpose()?;
    let request_commit = commit_position(&commits, recovered.request_commit_digest);
    let claim_commit = recovered
        .claim_commit_digest
        .and_then(|digest| commit_position(&commits, digest));
    let settlement_commit = recovered
        .settlement_commit_digest
        .and_then(|digest| commit_position(&commits, digest));
    let posture = match recovered.posture {
        RecoveredExternalActionPostureV1::Requested => "requested",
        RecoveredExternalActionPostureV1::Claimed => "claimed",
        RecoveredExternalActionPostureV1::Settled(_) => "settled",
    };
    let writer_epoch = writer_epoch.map(|epoch| {
        json!({
            "epochId": hex(&epoch.epoch_id.as_hash()),
            "previousEpochId": epoch
                .previous_epoch_id
                .map(|previous| json!(hex(&previous.as_hash())))
                .unwrap_or(Value::Null),
            "previousEpochFinalCommitDigest": epoch
                .previous_epoch_final_commit_digest
                .map(|digest| json!(hex(&digest)))
                .unwrap_or(Value::Null),
            "startedAtLsn": epoch.started_at_lsn.as_u64()
        })
    });
    Ok(json!({
        "phase": phase,
        "requestId": hex(&request.request_id().as_hash()),
        "writerEpoch": writer_epoch,
        "compiler": {
            "coreDigest": admitted.source_core_digest(),
            "targetIrDigest": admitted.target_ir_digest(),
            "operation": admitted.operation_coordinate(),
            "intent": request_case.intent
        },
        "posture": posture,
        "wal": {"commitCount": commits.len()},
        "ordering": {
            "requestCommit": request_commit,
            "claimCommit": claim_commit,
            "settlementCommit": settlement_commit
        },
        "publication": {
            "settlementCommittedBeforeResult": settlement_commit.is_some(),
            "replayedFromRetainedSettlement": phase == "replay" && settlement.is_some()
        },
        "settlement": settlement
    }))
}

fn decode_patch_settlement(bytes: &[u8]) -> Result<Value, String> {
    let value = decode_canonical_cbor_v1(bytes)
        .map_err(|error| format!("settlement result was not canonical: {error:?}"))?;
    Ok(json!({
        "status": canonical_text_field(&value, "posture")?,
        "path": canonical_optional_text_field(&value, "path")?,
        "requestBasis": hex(canonical_bytes_field(&value, "requestBasis")?),
        "evidence": hex(canonical_bytes_field(&value, "evidence")?),
        "beforeContentDigest": canonical_optional_bytes_hex_field(
            &value,
            "beforeContentDigest",
        )?,
        "afterContentDigest": canonical_optional_bytes_hex_field(
            &value,
            "afterContentDigest",
        )?,
        "resultingBasis": canonical_optional_bytes_hex_field(&value, "resultingBasis")?,
        "obstruction": canonical_optional_text_field(&value, "obstruction")?
    }))
}

fn canonical_field<'a>(
    value: &'a CanonicalValueV1,
    field: &str,
) -> Result<&'a CanonicalValueV1, String> {
    let CanonicalValueV1::Map(entries) = value else {
        return Err(format!("canonical value containing {field} was not a map"));
    };
    entries
        .iter()
        .find_map(|(key, value)| match key {
            CanonicalValueV1::Text(key) if key == field => Some(value),
            _ => None,
        })
        .ok_or_else(|| format!("canonical field {field} was absent"))
}

fn canonical_text_field(value: &CanonicalValueV1, field: &str) -> Result<String, String> {
    match canonical_field(value, field)? {
        CanonicalValueV1::Text(value) => Ok(value.clone()),
        _ => Err(format!("canonical field {field} was not text")),
    }
}

fn canonical_bytes_field<'a>(value: &'a CanonicalValueV1, field: &str) -> Result<&'a [u8], String> {
    match canonical_field(value, field)? {
        CanonicalValueV1::Bytes(value) => Ok(value),
        _ => Err(format!("canonical field {field} was not bytes")),
    }
}

fn canonical_optional_text_field(value: &CanonicalValueV1, field: &str) -> Result<Value, String> {
    match canonical_field(value, field)? {
        CanonicalValueV1::Null => Ok(Value::Null),
        CanonicalValueV1::Text(value) => Ok(json!(value)),
        _ => Err(format!("canonical field {field} was not optional text")),
    }
}

fn canonical_optional_bytes_hex_field(
    value: &CanonicalValueV1,
    field: &str,
) -> Result<Value, String> {
    match canonical_field(value, field)? {
        CanonicalValueV1::Null => Ok(Value::Null),
        CanonicalValueV1::Bytes(value) => Ok(json!(hex(value))),
        _ => Err(format!("canonical field {field} was not optional bytes")),
    }
}

fn adapter_id() -> ExternalActionAdapterIdV1 {
    ExternalActionAdapterIdV1::from_hash(digest("hello-effect-patch:bounded-adapter"))
}

fn adapter_profile(
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> ValidatedWorkspacePatchProfileV1 {
    let request = admitted.request();
    ValidatedWorkspacePatchProfileV1 {
        operation_id: request.operation_id,
        input_schema_digest: request.input_schema_digest,
        settlement_schema_digest: request.settlement_schema_digest,
        reconciliation_law_digest: request.reconciliation_law_digest,
        authority_scope_digest: request.authority_scope_digest,
        adapter_id: adapter_id(),
        max_file_bytes: MAX_FILE_BYTES_V1,
    }
}

/// Opens the WAL for writing under a fresh, durably linked writer epoch.
///
/// Echo owns epoch derivation, predecessor linkage, and lease enforcement in
/// `FilesystemWalStore::acquire_fresh_writer_epoch`: it takes the filesystem
/// writer lease, rereads the persisted epoch ledger, closes an epoch left by a
/// terminated process, and derives the successor from that predecessor's
/// identity and final commit digest. Every host phase here is a separate
/// process, so each phase acquires a new epoch chained to the persisted
/// predecessor.
///
/// Hello Echo derives no epoch identity of its own and reuses no fencing
/// token across restarts. A concurrently live writer keeps the lease and this
/// call refuses rather than taking over.
fn open_write_store(path: &Path) -> Result<(FilesystemWalStore, WriterEpoch), String> {
    let mut store = open_read_store(path)?;
    let epoch = store
        .acquire_fresh_writer_epoch(Lsn::from_raw(0))
        .map_err(|error| format!("writer epoch acquisition failed: {error:?}"))?;
    Ok((store, epoch))
}

fn open_read_store(path: &Path) -> Result<FilesystemWalStore, String> {
    FilesystemWalStore::open(path, SEGMENT_ID)
        .map_err(|error| format!("filesystem WAL open failed: {error:?}"))
}

fn wal_commit_count(path: &Path) -> Result<usize, String> {
    if !path.exists() {
        return Ok(0);
    }
    Ok(open_read_store(path)?.read_commits().len())
}

fn recover(store: &FilesystemWalStore) -> Result<ExternalActionCoordinatorV1, String> {
    ExternalActionCoordinatorV1::recover(store)
        .map_err(|error| format!("external-action recovery failed: {error:?}"))
}

fn transaction_context(
    phase: &str,
    admitted: &AdmittedEdictExternalActionRequestV1,
    writer_epoch: WriterEpochId,
) -> ExternalActionTransactionContextV1 {
    ExternalActionTransactionContextV1 {
        writer_epoch,
        segment_id: SEGMENT_ID,
        transaction_id: WalTransactionId::from_hash(digest(&format!(
            "hello-effect-patch:{phase}:{}",
            hex(&admitted.request().request_id().as_hash())
        ))),
        durability_mode: WalDurabilityMode::StrictFilesystem,
        payload_codec_id: PayloadCodecId::from_hash(digest("hello-effect-patch:codec")),
        payload_schema_id: PayloadSchemaId::from_hash(digest("hello-effect-patch:schema")),
        payload_schema_version: 1,
        canonical_encoding_version: 1,
        digest_domain: digest("hello-effect-patch:wal-domain"),
    }
}

fn canonical_map<const N: usize>(
    entries: [(&'static str, CanonicalValueV1); N],
) -> CanonicalValueV1 {
    CanonicalValueV1::Map(
        entries
            .into_iter()
            .map(|(key, value)| (CanonicalValueV1::Text(key.to_owned()), value))
            .collect(),
    )
}

fn conflicting_kind(kind: ExternalActionSettlementKindV1) -> ExternalActionSettlementKindV1 {
    match kind {
        ExternalActionSettlementKindV1::Succeeded => ExternalActionSettlementKindV1::Rejected,
        _ => ExternalActionSettlementKindV1::Succeeded,
    }
}

fn settlement_kind(kind: ExternalActionSettlementKindV1) -> &'static str {
    match kind {
        ExternalActionSettlementKindV1::Succeeded => "succeeded",
        ExternalActionSettlementKindV1::Rejected => "rejected",
        ExternalActionSettlementKindV1::Failed => "failed",
        ExternalActionSettlementKindV1::OutcomeUnknown => "outcomeUnknown",
    }
}

fn commit_position(
    commits: &[warp_core::causal_wal::WalTransactionCommit],
    digest: Hash,
) -> Option<usize> {
    commits
        .iter()
        .position(|commit| commit.commit_digest == digest)
        .map(|index| index + 1)
}

fn print_json(value: &Value) -> Result<(), String> {
    println!(
        "{}",
        serde_json::to_string(value).map_err(|error| error.to_string())?
    );
    Ok(())
}

fn digest(label: &str) -> Hash {
    blake3::hash(label.as_bytes()).into()
}

fn decode_hex(value: &str) -> Result<Vec<u8>, String> {
    if !value.len().is_multiple_of(2) {
        return Err("hex value has odd length".to_owned());
    }
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let high = hex_nibble(pair[0])?;
            let low = hex_nibble(pair[1])?;
            Ok((high << 4) | low)
        })
        .collect()
}

fn hex_nibble(value: u8) -> Result<u8, String> {
    match value {
        b'0'..=b'9' => Ok(value - b'0'),
        b'a'..=b'f' => Ok(value - b'a' + 10),
        _ => Err("hex value was not lowercase hexadecimal".to_owned()),
    }
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(char::from(DIGITS[usize::from(byte >> 4)]));
        out.push(char::from(DIGITS[usize::from(byte & 0x0f)]));
    }
    out
}
