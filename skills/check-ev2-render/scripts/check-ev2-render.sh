#!/usr/bin/env bash
#
# check-ev2-render.sh — Verify that an ARO-HCP change survives EV2 manifest
# generation in sdp-pipelines, in the SAME way the ADO "Generate Ev2 Manifests"
# step does: `aro ev2 manifests test --output-format resolve`.
#
# WHY: ARO-HCP's own CI renders templates with CONCRETE config values, so it
# passes even when a change breaks the sdp-pipelines EV2RA generator, which
# renders Helm values.yaml / *.bicepparam / pipeline.yaml with EV2 "dunder"
# placeholders (every config ref becomes the literal string `__path.to.value__`).
# The classic failure is `{{ range .some.array }}` in a values.yaml: fine with a
# real array, but "range can't iterate over __some.array__" under resolve.
#
# Usage:
#   check-ev2-render.sh <ARO-HCP-PR-number | commit-SHA> [--service-group SG]
#
# Env:
#   SDP_PIPELINES_DIR   Path to your existing sdp-pipelines checkout (ADO repo).
#                       Auto-detected under common ~/Code paths if unset.
#
# Notes:
#   * Non-destructive: all work happens in a throwaway `git worktree` of the
#     sdp-pipelines origin/main; your checkout and branch are left untouched.
#   * Builds `aro` fresh from origin/main so the pipeline schema / ARO-Tools API
#     match the change under test (a stale `aro` gives false schema errors). The
#     built binary is cached per origin/main SHA, so repeat runs skip the build.
#   * No Go version is hardcoded: the required toolchain is read from the repo's
#     own go.mod / .bingo/*.mod directives and fetched on demand via GOTOOLCHAIN
#     (cached by Go; instant after the first download). Any recent Go bootstraps it.
#   * macOS + Linux compatible. Requires: gh, git, go (any recent), az (bicep), make.
#   * Speed knobs: reuses prebuilt helper binaries, a cached `aro`, and a cached
#     bicep. Cache dir: $CHECK_EV2_CACHE or ${XDG_CACHE_HOME:-~/.cache}/check-ev2-render.
#
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 2; }

PR_REF="${1:-}"; [[ -n "$PR_REF" ]] || die "usage: check-ev2-render.sh <PR-number|SHA> [--service-group SG]"
shift || true

SG="Global"; ENTITY="entrypoint"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service-group) SG="$2"; ENTITY="service-group"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

# Portable in-place sed (GNU vs BSD).
sed_i() { if sed --version >/dev/null 2>&1; then sed -i "$@"; else local e="$1"; shift; sed -i '' "$e" "$@"; fi; }

# Persistent cache for the built aro binary (speeds up repeat runs).
CACHE="${CHECK_EV2_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/check-ev2-render}"
mkdir -p "$CACHE"

# ver_ge A B -> true if dotted-numeric version A >= B.
ver_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1)" == "$1" ]]; }

# Ensure a Go toolchain new enough for the worktree + its bingo-managed tools.
# Nothing is hardcoded: read the highest `go`/`toolchain` directive from the
# repo's own module files and, if the local go is older, point GOTOOLCHAIN at
# that exact version so Go fetches it on demand (cached; instant on later runs).
ensure_go() {
  command -v go >/dev/null || die "go not found on PATH"
  local cur req
  cur="$(go env GOVERSION 2>/dev/null | sed 's/^go//')"
  req="$(grep -rhE '^(go|toolchain) ' "$1/tooling/go.mod" "$1"/.bingo/*.mod 2>/dev/null \
         | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -V | tail -1)"
  if [[ -n "$req" ]] && ! ver_ge "$cur" "$req"; then
    echo "go toolchain: local go$cur < required go$req — setting GOTOOLCHAIN=go${req}+auto (fetched once, then cached by Go)"
    export GOTOOLCHAIN="go${req}+auto"
  else
    echo "go toolchain: local go$cur satisfies required go${req:-<none detected>}"
  fi
}

# 1) Locate an existing sdp-pipelines checkout (it's an ADO repo; you must have one).
SDP="${SDP_PIPELINES_DIR:-}"
if [[ -z "$SDP" ]]; then
  for c in "$HOME/Code/Azure/sdp-pipelines" "$HOME/code/Azure/sdp-pipelines" \
           "$HOME/Code/sdp-pipelines" "$HOME/code/sdp-pipelines" "$HOME/sdp-pipelines"; do
    [[ -d "$c/hcp" && -d "$c/tooling" ]] && SDP="$c" && break
  done
fi
[[ -n "$SDP" && -d "$SDP/hcp" && -d "$SDP/tooling" ]] || \
  die "set SDP_PIPELINES_DIR to your sdp-pipelines checkout (not found automatically)"
echo "sdp-pipelines: $SDP"

# 2) Resolve the ARO-HCP commit SHA (accept a PR number or a raw SHA).
if [[ "$PR_REF" =~ ^[0-9]+$ ]]; then
  SHA=$(gh pr view "$PR_REF" --repo Azure/ARO-HCP --json mergeCommit,headRefOid \
        -q '.mergeCommit.oid // .headRefOid') || die "could not resolve PR #$PR_REF via gh"
else
  SHA="$PR_REF"
fi
SHORT="${SHA:0:12}"
echo "ARO-HCP commit: $SHA  (target: ${ENTITY}=Microsoft.Azure.ARO.HCP.${SG}, resolve mode)"

# 3) Throwaway worktree of a fresh origin/main (matched toolchain).
git -C "$SDP" fetch -q origin main
TMP="$(mktemp -d)"; WT="$TMP/sdp-ev2repro"
# shellcheck disable=SC2317,SC2329  # cleanup() runs indirectly via 'trap cleanup EXIT'
cleanup() {
  rm -rf "$WT/_scratch" "$WT/_output" 2>/dev/null || true
  git -C "$SDP" worktree remove --force "$WT" 2>/dev/null || true
  git -C "$SDP" worktree prune 2>/dev/null || true
  rm -rf "$TMP" 2>/dev/null || true
}
trap cleanup EXIT
git -C "$SDP" worktree add -q --detach "$WT" origin/main
echo "worktree: $WT ($(git -C "$WT" rev-parse --short HEAD))"

# 4) Build aro (cached per origin/main SHA); reuse prebuilt helper binaries.
ensure_go "$WT"
MAIN_SHA="$(git -C "$WT" rev-parse HEAD)"
ARO_CACHE="$CACHE/aro-${MAIN_SHA}"
if [[ -x "$ARO_CACHE" ]]; then
  echo "aro: reusing cached build for main@${MAIN_SHA:0:12}"
  cp "$ARO_CACHE" "$WT/tooling/aro" && touch "$WT/tooling/aro"  # newer than sources -> make skips rebuild
else
  echo "building aro from main@${MAIN_SHA:0:12} (first run downloads modules; a few minutes)…"
fi
make -C "$WT/tooling" aro >/dev/null
if [[ ! -x "$ARO_CACHE" ]]; then
  cp "$WT/tooling/aro" "$ARO_CACHE"
  # shellcheck disable=SC2012  # ls -t sorts by mtime; cache filenames are controlled (aro-<sha>)
  ls -1t "$CACHE"/aro-* 2>/dev/null | tail -n +6 | xargs -r rm -f  # keep the 5 most recent
fi
for t in providerregistration/providerregistration secretsync/secretsync \
         helmdeploy/helmdeploy ev2registrar/ev2registrar \
         prowjobexecutor/prowjobexecutor grafanactl/grafanactl; do
  if [[ -x "$SDP/tools/$t" ]]; then
    mkdir -p "$WT/tools/$(dirname "$t")"; cp "$SDP/tools/$t" "$WT/tools/$t"
  fi
done

# 5) Install the pinned bicep (portable version parse; skip if already present).
BV="$WT/tooling/pkg/ev2/manifests/generate/testdata/zz_fixture_TestA_BicepVersion.txt"
if [[ -f "$BV" ]]; then
  ver=$(sed -n 's/.*Bicep CLI version \([0-9.]*\).*/\1/p' "$BV" | head -1)
  if [[ -n "$ver" ]]; then
    if az bicep version 2>/dev/null | grep -qF "$ver"; then
      echo "bicep: v$ver already installed"
    else
      az bicep install --version "v${ver}" >/dev/null 2>&1 || true
    fi
  fi
fi

# 6) Point the nested ARO-HCP at the change and regenerate config locally
#    (copy synced artifacts from the checkout — no network / works for fork PRs).
REV_DIR="$WT/hcp/ARO-HCP"
mkdir -p "$REV_DIR"
( cd "$REV_DIR" && git init -q \
  && git fetch -q --depth=1 https://github.com/Azure/ARO-HCP.git "$SHA" \
  && git checkout -q FETCH_HEAD )
sed_i "s/^ARO_HCP_REPO_REVISION=.*/ARO_HCP_REPO_REVISION=${SHORT}/" "$WT/hcp/Revision.mk"
cp "$REV_DIR/topology.yaml"           "$WT/hcp/aro-hcp-topology.yaml"
cp "$REV_DIR/config/config.schema.json" "$WT/hcp/config.schema.json"
rm -f "$WT/hcp/config.yaml"                         # force rebuild from the change
touch "$REV_DIR" "$WT/hcp/aro-hcp-topology.yaml" "$WT/hcp/config.schema.json"
echo "regenerating merged config at ${SHORT}…"
make -C "$WT/hcp" sync ARO_HCP_REPO_REVISION="$SHORT" >/dev/null

# 7) Run the REAL generator in resolve mode.
echo "running: aro ev2 manifests test --output-format resolve …"
set +e
OUT=$(make -C "$WT/hcp" generate-aro-hcp-ev2-manifests \
        SERVICE_GROUP="$SG" ENTITY="$ENTITY" OUTPUT_FORMAT=resolve \
        ARO_HCP_REPO_REVISION="$SHORT" 2>&1)
RC=$?
set -e

# Storage-account upload 401s are harmless local-run noise, not the failure.
echo "$OUT" | grep -vaE '401|InvalidAuthenticationInfo|failed to upload release metadata' | tail -40

echo
echo "──────────────────────────────────────────────────────────────"
if [[ $RC -eq 0 ]]; then
  echo "PASS ✅  Renders in EV2 resolve mode — should pass sdp-pipelines EV2 generation."
else
  echo "FAIL ❌  EV2 manifest generation failed. This change will break the"
  echo "        sdp-pipelines 'Generate Ev2 Manifests' step. Offending detail:"
  echo "$OUT" | grep -aE "failed to (generate|preprocess)|range can't iterate|can't evaluate|Command failed" | tail -20
fi
echo "──────────────────────────────────────────────────────────────"
exit $RC
