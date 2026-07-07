#!/usr/bin/env bash
set -euo pipefail

# get-ev2-releases.sh — wraps the ARO HCP oncall dashboard CLI ('oncall ev2')
# and filters the resulting EV2 rollouts down to a single environment.
#
# The environment is encoded in the trailing "- <env>" segment of the pipeline
# definition name, e.g. "Incremental - Entrypoint - HCP.Global - stg".

SUBCOMMAND="ev2"

usage() {
    cat >&2 <<'EOF'
get-ev2-releases.sh — List ARO HCP EV2 rollouts for one environment

USAGE:
    get-ev2-releases.sh -Environment <env> [options]

REQUIRED:
    -Environment <env>   Target environment. Matched against the trailing
                           "- <env>" segment of the pipeline definition name.
                           Known tokens: test | stg | prod | int
                           Aliases: stage/staging -> stg, production -> prod,
                                    integration -> int, tst -> test

OPTIONS:
    -Hours <int>         Look back N hours (default: 24; 0 = currently running only)
    -Path <path>         ADO folder path (default: the oncall CLI default,
                           \OneBranch\sdp-pipelines\hcp\Incremental)

EXAMPLES:
    get-ev2-releases.sh -Environment prod
    get-ev2-releases.sh -Environment stg -Hours 12
    get-ev2-releases.sh -Environment test -Hours 0
EOF
    exit 1
}

ENVIRONMENT=""
HOURS="24"
ADO_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -Environment|-Env) ENVIRONMENT="$2"; shift 2 ;;
        -Hours)            HOURS="$2";       shift 2 ;;
        -Path)             ADO_PATH="$2";    shift 2 ;;
        -h|--help)         usage ;;
        *)
            if [[ -z "$ENVIRONMENT" && "$1" != -* ]]; then
                ENVIRONMENT="$1"; shift
            else
                echo "Unknown argument: $1" >&2; usage
            fi
            ;;
    esac
done

[[ -z "$ENVIRONMENT" ]] && usage

# Locate the oncall CLI (on PATH, or installed by its setup.sh into ~/bin).
if command -v oncall >/dev/null 2>&1; then
    ONCALL="oncall"
elif [[ -x "$HOME/bin/oncall" ]]; then
    ONCALL="$HOME/bin/oncall"
else
    cat >&2 <<'EOF'
Error: the 'oncall' CLI was not found (looked on PATH and in ~/bin/oncall).

This skill wraps the oncall CLI that lives in 'oncall-cli/' in the aro-ai-tools
repo. Build and install it:
    oncall-cli/setup.sh
That installs 'oncall' to ~/bin. Requires Go, and either ADO_PAT set or az logged in.
EV2 lookups additionally need an az login that can get a token for the EV2 host
(corp login). Then re-run this skill.
EOF
    exit 127
fi

# Normalise the environment to the canonical trailing-segment token.
raw="$(printf '%s' "$ENVIRONMENT" | tr '[:upper:]' '[:lower:]')"
case "$raw" in
    test|tst)              canon="test" ;;
    stg|stage|staging)     canon="stg"  ;;
    prod|prd|production)   canon="prod" ;;
    int|integration|integ) canon="int"  ;;
    *)                     canon="$raw" ;;
esac

# Assemble oncall arguments.
args=("$SUBCOMMAND" --hours "$HOURS")
[[ -n "$ADO_PATH" ]] && args+=(--path "$ADO_PATH")

# Run the CLI (its stderr flows through); capture stdout for filtering.
set +e
OUT="$("$ONCALL" "${args[@]}")"
rc=$?
set -e
[[ $rc -ne 0 ]] && exit "$rc"

# Filter the markdown table by the environment (trailing "- <env>" segment of the
# Pipeline column, which is the 2nd column). Non-table messages pass through.
printf '%s\n' "$OUT" | awk -v canon="$canon" -v raw="$raw" -v env="$ENVIRONMENT" '
BEGIN { FS="|"; OFS="|"; matched=0; sawTable=0 }
$0 !~ /^[[:space:]]*\|/ { print; next }                     # non-table message
$0 ~ /^[[:space:]]*\|[-:| ]+$/ { sep=$0; sawTable=1; next }  # separator row
$0 ~ /[Pp]ipeline/ { hdr=$0; sawTable=1; next }             # header row
{
    sawTable=1
    name=$3
    gsub(/^[ \t]+|[ \t]+$/, "", name)
    lname=tolower(name)
    n=split(lname, parts, / - /)
    seg=parts[n]
    gsub(/^[ \t]+|[ \t]+$/, "", seg)
    seen[seg]=1
    if (seg==canon || seg==raw) {
        matched++
        $2=sprintf(" %d ", matched)
        rows[matched]=$0
    }
}
END {
    if (matched>0) {
        if (hdr!="") print hdr
        if (sep!="") print sep
        for (i=1;i<=matched;i++) print rows[i]
    } else if (sawTable) {
        envlist=""
        for (s in seen) envlist = envlist (envlist==""?"":", ") s
        printf("No EV2 rollouts matched environment \"%s\".\n", env) > "/dev/stderr"
        if (envlist!="") printf("Environments present in the results: %s\n", envlist) > "/dev/stderr"
    }
}
'
