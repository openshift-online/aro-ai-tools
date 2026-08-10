#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/check-semantic-template-hazards.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BASE="$TMP/base"
CANDIDATE="$TMP/candidate"

create_tree() {
  local root="$1"
  mkdir -p "$root/global" "$root/dev"
  cat >"$root/topology.yaml" <<'EOF'
entrypoints:
- identifier: Microsoft.Azure.ARO.HCP.Global
services:
- serviceGroup: Microsoft.Azure.ARO.HCP.Global
  pipelinePath: global/pipeline.yaml
EOF
  cat >"$root/topology-dev-ci.yaml" <<'EOF'
entrypoints:
- identifier: Microsoft.Azure.ARO.HCP.DevCI.Privileged
services:
- serviceGroup: Microsoft.Azure.ARO.HCP.DevCI.Privileged
  pipelinePath: dev/pipeline.yaml
EOF
  cat >"$root/global/pipeline.yaml" <<'EOF'
$schema: pipeline.schema.v1
serviceGroup: Microsoft.Azure.ARO.HCP.Global
resourceGroups:
- steps:
  - action: ARM
    parameters: global.bicepparam
  - action: Helm
    valuesFile: values.yaml
EOF
  cat >"$root/global/global.bicepparam" <<'EOF'
param existing = empty('{{ .global.existing }}') ? '' : '{{ .global.existing }}'
EOF
  cat >"$root/global/values.yaml" <<'EOF'
safe: '{{ .global.safe }}'
EOF
  cat >"$root/dev/pipeline.yaml" <<'EOF'
$schema: pipeline.schema.v1
serviceGroup: Microsoft.Azure.ARO.HCP.DevCI.Privileged
resourceGroups:
- steps:
  - action: ARM
    parameters: unsafe.bicepparam
EOF
  cat >"$root/dev/unsafe.bicepparam" <<'EOF'
param unsafe = empty('{{ .ci.value }}') ? [] : ['{{ .ci.value }}']
EOF
}

create_tree "$BASE"
cp -a "$BASE" "$CANDIDATE"

"$SCANNER" "$BASE" "$CANDIDATE" Global >/dev/null

cat >"$CANDIDATE/dev/unsafe.bicepparam" <<'EOF'
param unsafe = '{{ range .ci.values }}{{ . }}{{ end }}'
EOF
"$SCANNER" "$BASE" "$CANDIDATE" Global >/dev/null

cat >"$CANDIDATE/global/values.yaml" <<'EOF'
unsafe: '{{ if .global.enabled }}yes{{ end }}'
EOF
if "$SCANNER" "$BASE" "$CANDIDATE" Global >"$TMP/reachable.out" 2>&1; then
  echo "expected a newly introduced reachable hazard to fail" >&2
  exit 1
fi
grep -q 'global/values.yaml:1' "$TMP/reachable.out"

cp "$BASE/global/values.yaml" "$CANDIDATE/global/values.yaml"
cat >>"$CANDIDATE/topology.yaml" <<'EOF'
  children:
  - serviceGroup: Microsoft.Azure.ARO.HCP.New
    pipelinePath: dev/pipeline.yaml
EOF
if "$SCANNER" "$BASE" "$CANDIDATE" Global >"$TMP/reachable-via-topology.out" 2>&1; then
  echo "expected a newly reachable existing hazard to fail" >&2
  exit 1
fi
grep -q 'dev/unsafe.bicepparam:1' "$TMP/reachable-via-topology.out"

echo "PASS"
