# Hello Echo

Hello Echo is the canonical smallest standalone Edict application hosted by
Echo. It proves that application semantics can originate in Edict, cross Echo's
generic target adapter and independent verifier, and execute without native
application callbacks or handwritten Echo packages.

Hello Echo is Roadmap A for the Graft-on-Echo campaign. Its complete local
build, execution, durability, and recovery witness is the prerequisite for
Roadmap B: writing Graft in Edict and hosting it on Echo.

External workspace effects are introduced only after that pure runtime proof.
The [campaign roadmap](docs/roadmap.md) orders bounded workspace observation,
basis-bound patch application, Graft hosting, Git and GitHub adapters, and the
self-hosted delivery loop. The delivery loop is Roadmap Ω, not Hello Echo's
bootstrap workload.

## Build and test

Set `EDICT_REPO` and `ECHO_REPO` to compatible local feature-branch checkouts,
then run:

```sh
EDICT_REPO=/path/to/edict \
ECHO_REPO=/path/to/echo \
./tests/build.sh
```

The same command is the current end-to-end build test. Runtime execution and
recovery tests will be added before Roadmap A is complete.
