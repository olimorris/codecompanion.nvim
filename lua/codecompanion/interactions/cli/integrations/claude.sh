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
message=""

case "$action" in
  submitted | done)
    rm -f "$marker"
    ;;
  approval_requested)
    : >"$marker"
    message="Waiting for you"
    # Only PermissionRequest names a tool, so Notification keeps the message above
    if command -v jq >/dev/null 2>&1; then
      tool="$(jq -r '.tool_name // empty' 2>/dev/null)"
      if [ -n "$tool" ]; then
        message="Permission: $tool"
      fi
    fi
    ;;
  approval_finished)
    # Runs after every tool call, so cost nothing unless an approval is outstanding
    if [ ! -f "$marker" ]; then
      exit 0
    fi
    rm -f "$marker"
    ;;
  *)
    exit 0
    ;;
esac

expression="v:lua.require'codecompanion'.cli_hook({'bufnr': $CODECOMPANION_CLI_BUFNR, 'event': '$action'"
if [ -n "$message" ]; then
  expression="$expression, 'message': '$(printf '%s' "$message" | tr -d "'")'"
fi
expression="$expression})"

# A closed Neovim must not fail the hook, because a non-zero UserPromptSubmit blocks the prompt
nvim --server "$NVIM" --remote-expr "$expression" >/dev/null 2>&1 || true

exit 0
