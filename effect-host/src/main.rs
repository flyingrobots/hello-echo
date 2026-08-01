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
    record_external_action_request, ExternalActionAdapterIdV1, ExternalActionAdapterRegistryV1,
    ExternalActionCoordinatorV1, ExternalActionSettlementCandidateV1,
    ExternalActionSettlementKindV1, ExternalActionTransactionContextV1,
    RecoveredExternalActionPostureV1,
};
use warp_core::external_action_adapter::{
    admit_edict_external_action_request_v1, bounded_workspace_observation_basis_v1,
    encode_bounded_workspace_observation_input_v1, AdmittedEdictExternalActionRequestV1,
    BoundedWorkspaceObservationAdapterV1, BoundedWorkspaceObservationProfileV1,
    BoundedWorkspaceObservationReconcilerV1, EdictExternalActionAdmissionErrorV1,
};
use warp_core::{Hash, WorldlineId};

const SEGMENT_ID: WalSegmentId = WalSegmentId::from_raw(1);

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RequestCase {
    worldline_byte: u8,
    intent: String,
    scope: String,
    requested_paths: Vec<String>,
    expected_files: Vec<ExpectedFile>,
    permitted_paths: Vec<String>,
    max_settlement_bytes: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExpectedFile {
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
    let request_case: RequestCase = serde_json::from_slice(
        &fs::read(&invocation.request_file).map_err(|error| error.to_string())?,
    )
    .map_err(|error| error.to_string())?;
    let core_bytes = fs::read(&invocation.core_file).map_err(|error| error.to_string())?;
    let target_ir_bytes =
        fs::read(&invocation.target_ir_file).map_err(|error| error.to_string())?;

    let application_input = application_input(&request_case)?;
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
        "settle" => settlement_phase(&invocation, &request_case, &admitted),
        "unknown" => uncertainty_phase(&invocation, &request_case, &admitted),
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
    let operation_input =
        encode_bounded_workspace_observation_input_v1(request_case.requested_paths.clone())
            .map_err(|error| format!("operation input encoding failed: {error:?}"))?;
    encode_canonical_cbor_v1(&canonical_map([
        ("payload", CanonicalValueV1::Bytes(operation_input)),
        (
            "scope",
            CanonicalValueV1::Bytes(authority_scope(request_case).to_vec()),
        ),
        (
            "basis",
            CanonicalValueV1::Bytes(expected_basis(request_case)?.to_vec()),
        ),
        (
            "maxSettlementBytes",
            CanonicalValueV1::Integer(i128::from(request_case.max_settlement_bytes)),
        ),
        ("maxAttempts", CanonicalValueV1::Integer(1)),
    ]))
    .map_err(|error| format!("application input encoding failed: {error:?}"))
}

fn authority_scope(request_case: &RequestCase) -> Hash {
    let mut permitted_paths = request_case
        .permitted_paths
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>();
    permitted_paths.sort_unstable();
    permitted_paths.dedup();

    let mut hasher = blake3::Hasher::new();
    hasher.update(b"hello-effect:authority-scope:v1\0");
    hash_length_delimited(&mut hasher, request_case.scope.as_bytes());
    hasher.update(
        &u64::try_from(permitted_paths.len())
            .unwrap_or(u64::MAX)
            .to_le_bytes(),
    );
    for path in permitted_paths {
        hash_length_delimited(&mut hasher, path.as_bytes());
    }
    hasher.finalize().into()
}

fn hash_length_delimited(hasher: &mut blake3::Hasher, bytes: &[u8]) {
    hasher.update(&u64::try_from(bytes.len()).unwrap_or(u64::MAX).to_le_bytes());
    hasher.update(bytes);
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

fn expected_basis(request_case: &RequestCase) -> Result<Hash, String> {
    let files = request_case
        .expected_files
        .iter()
        .map(|file| decode_hex(&file.bytes_hex).map(|bytes| (file.path.as_str(), bytes)))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(bounded_workspace_observation_basis_v1(
        files.iter().map(|(path, bytes)| (*path, bytes.as_slice())),
    ))
}

fn request_phase(
    invocation: &Invocation,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> Result<(), String> {
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
    let (mut store, writer_epoch) = open_write_store(&invocation.wal_dir)?;
    let mut coordinator = recover(&store)?;
    let request = admitted.request();
    let recorded = coordinator
        .recorded_request(request.request_id())
        .map_err(|error| format!("request recovery failed: {error:?}"))?;
    let reconciler = BoundedWorkspaceObservationReconcilerV1::new(adapter_profile(admitted))
        .map_err(|error| format!("adapter profile admission failed: {error:?}"))?;
    let binding = reconciler.adapter_binding();
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
        digest("hello-effect:adapter-lease"),
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
            "{} does not accept external-world authority",
            invocation.phase
        ));
    }
    let store = open_read_store(&invocation.wal_dir)?;
    let coordinator = recover(&store)?;
    print_report(
        &invocation.phase,
        request_case,
        admitted,
        &store,
        &coordinator,
        // Read-only phases take no writer lease and acquire no epoch.
        None,
    )
}

fn settlement_phase(
    invocation: &Invocation,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> Result<(), String> {
    let workspace_root = invocation
        .argument
        .as_ref()
        .map(Path::new)
        .ok_or_else(|| format!("{} requires a workspace root", invocation.phase))?;
    let (mut store, writer_epoch) = open_write_store(&invocation.wal_dir)?;
    let mut coordinator = recover(&store)?;
    let grant = coordinator
        .claim_grant(admitted.request().request_id())
        .map_err(|error| format!("claim recovery failed: {error:?}"))?;
    let adapter = BoundedWorkspaceObservationAdapterV1::open(
        workspace_root,
        request_case.permitted_paths.clone(),
        adapter_profile(admitted),
    )
    .map_err(|error| format!("adapter open failed: {error:?}"))?;
    let candidate = adapter
        .observe(&grant, admitted)
        .map_err(|error| format!("bounded observation failed: {error:?}"))?;
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

fn uncertainty_phase(
    invocation: &Invocation,
    request_case: &RequestCase,
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> Result<(), String> {
    if invocation.argument.is_some() {
        return Err("unknown does not accept external-world authority".to_owned());
    }
    let (mut store, writer_epoch) = open_write_store(&invocation.wal_dir)?;
    let mut coordinator = recover(&store)?;
    let grant = coordinator
        .claim_grant(admitted.request().request_id())
        .map_err(|error| format!("claim recovery failed: {error:?}"))?;
    let reconciler = BoundedWorkspaceObservationReconcilerV1::new(adapter_profile(admitted))
        .map_err(|error| format!("reconciler admission failed: {error:?}"))?;
    reconciler
        .admit_outcome_unknown(
            &mut store,
            &mut coordinator,
            transaction_context("settlement", admitted, writer_epoch.epoch_id),
            admitted,
            grant,
            digest("hello-effect:outcome-unknown-evidence"),
        )
        .map_err(|error| format!("unknown outcome admission failed: {error:?}"))?;
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
            let observation = decode_observation(&settlement.canonical_result_bytes)?;
            let commit_digest = recovered
                .settlement_commit_digest
                .ok_or_else(|| "settlement commit digest absent".to_owned())?;
            Ok::<_, String>(json!({
                "kind": settlement_kind(settlement.kind),
                "commitDigest": hex(&commit_digest),
                "resultDigest": hex(&settlement.result_digest),
                "canonicalResultByteCount": settlement.canonical_result_bytes.len(),
                "observation": observation
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
        "writerEpoch": writer_epoch,
        "requestId": hex(&request.request_id().as_hash()),
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

fn decode_observation(bytes: &[u8]) -> Result<Value, String> {
    let value = decode_canonical_cbor_v1(bytes)
        .map_err(|error| format!("settlement result was not canonical: {error:?}"))?;
    let status = canonical_text_field(&value, "posture")?;
    let files_value = canonical_field(&value, "files")?;
    let CanonicalValueV1::Array(files) = files_value else {
        return Err("settlement files field was not an array".to_owned());
    };
    let files = files
        .iter()
        .map(|file| {
            Ok(json!({
                "path": canonical_text_field(file, "path")?,
                "bytesHex": hex(canonical_bytes_field(file, "bytes")?)
            }))
        })
        .collect::<Result<Vec<_>, String>>()?;
    let refusal = match canonical_field(&value, "obstruction")? {
        CanonicalValueV1::Null => Value::Null,
        CanonicalValueV1::Text(value) => json!(value),
        _ => return Err("settlement obstruction field was invalid".to_owned()),
    };
    Ok(json!({
        "status": status,
        "files": files,
        "refusal": refusal
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

fn adapter_id() -> ExternalActionAdapterIdV1 {
    ExternalActionAdapterIdV1::from_hash(digest("hello-effect:bounded-adapter"))
}

fn adapter_profile(
    admitted: &AdmittedEdictExternalActionRequestV1,
) -> BoundedWorkspaceObservationProfileV1 {
    let request = admitted.request();
    BoundedWorkspaceObservationProfileV1 {
        operation_id: request.operation_id,
        input_schema_digest: request.input_schema_digest,
        settlement_schema_digest: request.settlement_schema_digest,
        reconciliation_law_digest: request.reconciliation_law_digest,
        authority_scope_digest: request.authority_scope_digest,
        adapter_id: adapter_id(),
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
            "hello-effect:{phase}:{}",
            hex(&admitted.request().request_id().as_hash())
        ))),
        durability_mode: WalDurabilityMode::StrictFilesystem,
        payload_codec_id: PayloadCodecId::from_hash(digest("hello-effect:codec")),
        payload_schema_id: PayloadSchemaId::from_hash(digest("hello-effect:schema")),
        payload_schema_version: 1,
        canonical_encoding_version: 1,
        digest_domain: digest("hello-effect:wal-domain"),
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
