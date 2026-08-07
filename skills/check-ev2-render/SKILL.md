---
name: check-ev2-render
description: Verify locally that an ARO-HCP change will survive EV2 manifest generation in sdp-pipelines — catching the resolve/dunder-placeholder failures (e.g. `range` over an array config) that ARO-HCP's own CI cannot see.
allowed-tools: shell
---

Verify that an ARO-HCP change renders in the sdp-pipelines EV2RA generator
**before** it ships, in the same way the ADO "Generate Ev2 Manifests" step does.

## Why this exists

ARO-HCP's own CI (`make verify`, `templatize pipeline validate`, `config make
validate`, helm-test fixtures) renders every template with **concrete config
values**, so it PASSES even when a change breaks the sdp-pipelines EV2RA
generator.

The generator renders Helm `values.yaml`, `*.bicepparam`, and `pipeline.yaml` in
**`resolve` mode**, where every config reference becomes the literal "dunder"
string `__path.to.value__` (EV2 substitutes the real value at deploy time).
Anything that treats a referenced config value as a real type then explodes. The
canonical failure was a `values.yaml` doing
`{{ range .hypershift.metricsSet.extraHCPMetrics }}` — fine with a real array,
but under resolve:

```
step RP.HypershiftOperator.management.deploy: ... failed to preprocess
.../hypershiftoperator/values.yaml: ... range can't iterate over
__hypershift.metricsSet.extraHCPMetrics__
```

A second failure mode is semantic rather than syntactic. For example,
`{{ if .optionalClientId }}` always takes the true branch in resolve mode
because `__optionalClientId__` is a non-empty string. Ev2 can later replace it
with an empty value, but the template branch is not reevaluated.

Rule of thumb: config references in pipeline / values / bicepparam files may be
directly interpolated, but must not drive `if`, `with`, `range`, comparisons,
fallback functions, indexing, or other semantic template operations. Move that
logic to a stage that runs after Ev2 substitution, such as the Helm chart
template. Also see ARO-HCP `docs/configuration.md`, "avoid arrays in
configuration".

## Arguments

- **PR** (required): an ARO-HCP PR number (e.g. `6119`) or a commit SHA. A PR
  number is resolved to its merge commit (or head) via `gh`.
- **Service group** (optional, `--service-group <SG>`): restrict to one service
  group (e.g. `RP.HypershiftOperator`). Default is the `Global` entrypoint, which
  transitively resolves **every** service group in one run.

## Prerequisites

- A local **sdp-pipelines** checkout (it's an Azure DevOps repo — clone it once).
  Point the skill at it with `SDP_PIPELINES_DIR=/path/to/sdp-pipelines`, or let it
  auto-detect under common `~/Code`/`~/code` paths.
- `gh`, `git`, `make`, and `az` (for `az bicep install`) on PATH.
- **Any recent `go`** on PATH — the exact toolchain the repo needs is detected
  from its own `go.mod` / `.bingo/*.mod` directives and fetched on demand via
  `GOTOOLCHAIN` (Go caches it, so it's downloaded at most once). No Go version is
  hardcoded in the skill.

### Speed / caching

Repeat runs are fast: the built `aro` binary is cached per sdp-pipelines
`origin/main` SHA (rebuilt only when main moves), the Go toolchain is cached by
Go itself, and `bicep` is only (re)installed when the pinned version is missing.
Cache dir: `$CHECK_EV2_CACHE`, else `${XDG_CACHE_HOME:-~/.cache}/check-ev2-render`.

## Instructions

Run the bundled script; it does everything non-destructively and prints a
PASS/FAIL verdict:

```bash
SDP_PIPELINES_DIR=/path/to/sdp-pipelines \
  scripts/check-ev2-render.sh <PR-number-or-SHA> [--service-group <SG>]
```

What it does (so you can review or reproduce by hand):

1. Resolves the ARO-HCP commit SHA from the PR.
2. Creates a throwaway `git worktree` of the sdp-pipelines **origin/main** — your
   branch/checkout is never touched.
3. Detects the Go toolchain the repo needs (highest `go`/`toolchain` directive in
   its `go.mod` / `.bingo/*.mod`) and, if the local `go` is older, points
   `GOTOOLCHAIN` at that version so Go fetches it on demand.
4. **Builds `aro` fresh from main** so the bundled `pipeline.schema.v1` and
   ARO-Tools API match the change. (A stale `aro` reports false schema errors like
   unknown `manage`/`timeout` step fields — don't trust an old binary.) The build
   is cached per `origin/main` SHA; reuses your prebuilt helper binaries and the
   pinned `bicep` (only installing when missing).
5. Checks the nested `hcp/ARO-HCP` out at the change's SHA, copies that revision's
   `topology.yaml` + `config.schema.json`, and rebuilds the merged `hcp/config.yaml`
   so any new config keys the change adds actually exist.
6. Scans changed `values.yaml`, `pipeline.yaml`, and `*.bicepparam` lines for
   config-dependent control flow and semantic functions that would evaluate
   dunder placeholders instead of real values.
7. Runs the real generator in resolve mode:
   `aro ev2 manifests test --output-format resolve` for the `Global` entrypoint
   (via `make -C hcp generate-aro-hcp-ev2-manifests … OUTPUT_FORMAT=resolve`).
8. Removes the worktree and scratch dirs on exit.

## Verdict

- **PASS / exit 0** — no new known placeholder-semantics hazards were found and
  the change renders in resolve mode. This does not fully emulate
  deployment-time Ev2 substitution.
- **FAIL / non-zero** — look for `failed to preprocess …`, `range can't iterate
  over __…__`, `can't evaluate …`, an `Unsafe config-dependent template logic`
  report, or any template-execution / missing-config error. Report the failing
  step (e.g. `RP.HypershiftOperator.management.deploy`), the file, the line, and
  the offending config path.
- **IGNORE** `401 InvalidAuthenticationInfo` / "failed to upload release metadata"
  lines — those are harmless local upload attempts (CI passes
  `--skip-storage-account-uploads=true`), not the failure. The real signal is the
  final `Command failed.` line, which the script isolates for you.

## Safety

This skill only **generates and validates** manifests (`--generate-only`, test
rollout-infra); it deploys nothing. Never run the sdp-pipelines `pipeline/%` or
`entrypoint/%` make targets — those touch live deployments.
