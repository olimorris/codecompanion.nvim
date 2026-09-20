---
description: "Diagnose common CodeCompanion.nvim problems in Neovim, covering checkhealth, the minimal config, log files and where to ask for help."
---

# Troubleshooting

> [!WARNING]
> **PLACEHOLDER PAGE.** The headings below are a skeleton for the gaps found during the docs review. The two sections that already had content elsewhere have been moved in verbatim. Everything marked _TODO_ needs your words.

## Health Check

Run `:checkhealth codecompanion` to verify that all requirements are met.

## Minimal Configuration

Consider using the [minimal.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/minimal.lua) file to troubleshoot, running it with `nvim --clean -u minimal.lua`.

## Logs

_TODO: where the log file lives, how to set `log_level` (this is documented at [Other Configuration Options](/configuration/others#log-level)), and what to look for in it._

## Common Problems

_TODO: the recurring issues from the issue tracker. Candidates spotted during the review:_

- _No API key found / the adapter can't authenticate_
- _Nothing streams back into the chat buffer_
- _Completion isn't triggering on `#`, `/` or `@`_
- _An ACP agent won't start, or its commands never appear_
- _`insert_edit_into_file` isn't applying changes_
- _Markdown isn't rendering in the chat buffer_

## Reporting an Issue

_TODO: what you want in a bug report, and the link to the issue template._
