#!/bin/sh
# Reports Claude Code's turn events back to the Neovim instance that started it.
#
# CodeCompanion sets CODECOMPANION_HOOK to this path in the agent's environment, so
# `.claude/settings.json` calls it without knowing where the plugin is installed. Both
# guards below make the script do nothing when Claude Code runs anywhere else.

set -u

action="${1:-}"

[ -n "${CODECOMPANION_CLI_BUFNR:-}" ] || exit 0
[ -n "${NVIM:-}" ] || exit 0

# The socket's basename carries Neovim's pid, so this stays unique without forking a subshell
marker="${TMPDIR:-/tmp}/codecompanion-approval-${NVIM##*/}-$CODECOMPANION_CLI_BUFNR"

case "$action" in
  submitted | done)
    rm -f "$marker"
    ;;
  approval_requested)
    : >"$marker"
    ;;
  approval_finished)
    # Runs after every tool call, so cost nothing unless an approval is outstanding
    [ -f "$marker" ] || exit 0
    rm -f "$marker"
    ;;
  *)
    exit 0
    ;;
esac

# Neovim reads the hook's JSON from a file, which spares the expression below from quoting it
payload="$(mktemp "${TMPDIR:-/tmp}/codecompanion-hook.XXXXXX")" || exit 0
trap 'rm -f "$payload"' EXIT
cat >"$payload"

# Vim strings escape an apostrophe by doubling it, and TMPDIR could contain one
escaped_payload="$(printf '%s' "$payload" | sed "s/'/''/g")"
expression="v:lua.require'codecompanion'.cli_hook({'bufnr': $CODECOMPANION_CLI_BUFNR, 'event': '$action', 'payload_path': '$escaped_payload'})"

# A closed Neovim must not fail the hook, because a non-zero UserPromptSubmit blocks the prompt
nvim --server "$NVIM" --remote-expr "$expression" >/dev/null 2>&1 || true

exit 0
