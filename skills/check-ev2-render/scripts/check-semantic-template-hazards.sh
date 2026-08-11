#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 2; }

[[ $# -eq 3 ]] || die "usage: check-semantic-template-hazards.sh <baseline-dir> <candidate-dir> <service-group>"

BASELINE="$1"
CANDIDATE="$2"
SERVICE_GROUP="$3"

[[ -f "$BASELINE/topology.yaml" ]] || die "baseline topology not found: $BASELINE/topology.yaml"
[[ -f "$CANDIDATE/topology.yaml" ]] || die "candidate topology not found: $CANDIDATE/topology.yaml"

case "$SERVICE_GROUP" in
  Microsoft.Azure.ARO.HCP.*) TARGET="$SERVICE_GROUP" ;;
  *) TARGET="Microsoft.Azure.ARO.HCP.$SERVICE_GROUP" ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pipeline_paths() {
  local topology="$1" allow_missing="${2:-false}"

  if awk -v target="$TARGET" '
    function indentation(line, copy) {
      copy = line
      sub(/[^ ].*$/, "", copy)
      return length(copy)
    }
    function yaml_value(line) {
      sub(/^[^:]+:[[:space:]]*/, "", line)
      gsub(/^["'\''"]|["'\''"]$/, "", line)
      return line
    }
    /^[[:space:]]*- serviceGroup:[[:space:]]*/ {
      current_indent = indentation($0)
      current_value = yaml_value($0)
      if (found && current_indent <= root_indent) {
        exit
      }
      if (!found && current_value == target) {
        found = 1
        root_indent = current_indent
      }
      next
    }
    found && /^[[:space:]]*pipelinePath:[[:space:]]*/ {
      print yaml_value($0)
    }
    END {
      if (!found) {
        exit 3
      }
    }
  ' "$topology"; then
    return 0
  fi

  [[ "$allow_missing" == "true" ]] || die "service group not found in topology: $TARGET"
}

inventory() {
  local root="$1" output="$2" allow_missing="${3:-false}"
  local pipelines="$TMP/pipelines.$RANDOM" files="$TMP/files.$RANDOM"

  pipeline_paths "$root/topology.yaml" "$allow_missing" >"$pipelines"
  : >"$files"

  while IFS= read -r pipeline; do
    [[ -n "$pipeline" ]] || continue
    [[ -f "$root/$pipeline" ]] || die "reachable pipeline not found: $pipeline"
    printf '%s\n' "$pipeline" >>"$files"

    while IFS= read -r reference; do
      [[ -n "$reference" ]] || continue
      local reference_path reference_dir reference_base absolute relative
      reference_path="$(dirname "$root/$pipeline")/$reference"
      reference_dir="$(dirname "$reference_path")"
      reference_base="$(basename "$reference_path")"
      [[ -d "$reference_dir" ]] || die "referenced directory not found: $pipeline -> $reference"
      absolute="$(cd "$reference_dir" && pwd -P)/$reference_base"
      relative="${absolute#"$root"/}"
      [[ "$relative" != "$absolute" ]] || die "referenced file escapes repository: $pipeline -> $reference"
      [[ -f "$absolute" ]] || die "referenced preprocessed file not found: $pipeline -> $reference"
      printf '%s\n' "$relative" >>"$files"
    done < <(
      awk '
        /^[[:space:]]*(parameters|valuesFile):[[:space:]]*/ {
          line = $0
          sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", line)
          sub(/[[:space:]]+#.*$/, "", line)
          gsub(/^["'\''"]|["'\''"]$/, "", line)
          print line
        }
      ' "$root/$pipeline"
    )
  done <"$pipelines"

  sort -u "$files" -o "$files"
  : >"$output"
  while IFS= read -r file; do
    awk -v path="$file" '
      function unsafe(line) {
        return line ~ /\{\{/ &&
          line ~ /\.[A-Za-z_][A-Za-z0-9_.]*/ &&
          line ~ /(^|[^A-Za-z])(if|with|range|eq|ne|lt|le|gt|ge|and|or|not|default|required|empty|coalesce|ternary|len|index)([^A-Za-z]|$)/
      }
      unsafe($0) {
        normalized = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", normalized)
        printf "%s\t%s\t%d\t%s\n", path, normalized, NR, $0
      }
    ' "$root/$file" >>"$output"
  done <"$files"

  sort -u "$output" -o "$output"
}

BASELINE_INVENTORY="$TMP/baseline"
CANDIDATE_INVENTORY="$TMP/candidate"
NEW_KEYS="$TMP/new-keys"

inventory "$BASELINE" "$BASELINE_INVENTORY" true
inventory "$CANDIDATE" "$CANDIDATE_INVENTORY"

cut -f1-2 "$BASELINE_INVENTORY" >"$TMP/baseline-keys"
cut -f1-2 "$CANDIDATE_INVENTORY" >"$TMP/candidate-keys"
comm -13 "$TMP/baseline-keys" "$TMP/candidate-keys" >"$NEW_KEYS"

if [[ ! -s "$NEW_KEYS" ]]; then
  echo "template semantics: no new hazards in files reachable from $TARGET"
  exit 0
fi

echo
echo "──────────────────────────────────────────────────────────────"
echo "FAIL ❌  The merged result introduces unsafe config-dependent template logic:"
awk -F '\t' '
  NR == FNR {
    wanted[$1 FS $2] = 1
    next
  }
  ($1 FS $2) in wanted {
    printf "  %s:%s: %s\n", $1, $3, $4
  }
' "$NEW_KEYS" "$CANDIDATE_INVENTORY"
echo
echo "Resolve mode evaluates config references as non-empty __path__ strings"
echo "before Ev2 substitutes their real values. Use direct interpolation only;"
echo "move fallback, branching, iteration, and comparisons to a stage that runs"
echo "after Ev2 substitution (for example, the Helm chart template)."
echo "──────────────────────────────────────────────────────────────"
exit 1
