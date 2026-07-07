#!/usr/bin/env bash
#
# setup.sh — builds the oncall CLI, installs it to $HOME/bin, and registers
# zsh aliases (builds, ev2, e2e) pointing at the installed binary's absolute
# path. Safe to re-run: it rebuilds the binary and refreshes the aliases
# without duplicating them in .zshrc.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/bin"
BINARY="$BIN_DIR/oncall"
ZSHRC="$HOME/.zshrc"
MARKER_START="# >>> oncall CLI aliases >>>"
MARKER_END="# <<< oncall CLI aliases <<<"

echo "==> Building oncall CLI"
TMP_BIN="$(mktemp)"
(cd "$SCRIPT_DIR" && go build -o "$TMP_BIN" ./cmd/oncall)

echo "==> Installing to $BINARY"
mkdir -p "$BIN_DIR"
install -m 0755 "$TMP_BIN" "$BINARY"
rm -f "$TMP_BIN"

echo "==> Registering aliases in $ZSHRC"
touch "$ZSHRC"
if grep -qF "$MARKER_START" "$ZSHRC"; then
    sed -i "/$MARKER_START/,/$MARKER_END/d" "$ZSHRC"
fi

cat >>"$ZSHRC" <<EOF

$MARKER_START
alias builds='$BINARY builds'
alias ev2='$BINARY ev2'
alias e2e='$BINARY e2e'
$MARKER_END
EOF

# Collapse any consecutive blank lines (can build up across repeated runs)
# into a single blank line.
cat -s "$ZSHRC" >"$ZSHRC.tmp" && mv "$ZSHRC.tmp" "$ZSHRC"

echo "==> Done. Installed: $BINARY"
echo "    Aliases added to $ZSHRC: builds, ev2, e2e"
echo "    Run 'source $ZSHRC' or start a new shell to use them."
