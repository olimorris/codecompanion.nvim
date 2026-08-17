# Code Review

Code reviews let a user leave comments against an agent's changes where the code actually is, rather than typing out file names and line numbers by hand. Comments are collected up, sent to the agent in one go, and the review then advances a _baseline_ so the next review only shows what the agent changed in response. It's the same loop as a pull request: comment, submit, re-review.

The baseline lives in git and the comments are persisted to disk, so a review survives across sessions and Neovim instances. Reviews work with CodeCompanion's own tools, ACP agents, and CLI agents running outside of Neovim.

## Init

@./lua/codecompanion/interactions/code_review/init.lua

The entry point and the only module the rest of the plugin talks to. It owns the user-facing actions - commenting on a line, selection or quickfix hunk, opening the changes in the quickfix list, accepting and ignoring hunks, and draining the comments to send them. It also registers the autocmds that snapshot the baseline when an agent starts working and track the files it edits.

The `advance_baseline` helper is the shared path behind `consume`, `share` and `approve`. It moves the baseline and clears the per-round state, reporting to the user if the snapshot fails.

## Baseline

@./lua/codecompanion/interactions/code_review/baseline.lua

All of the git plumbing. A baseline is a commit holding a snapshot of the worktree, stored under `refs/worktree/codecompanion/baselines/<branch>`, with a stable alias at `refs/worktree/codecompanion/baseline` for gitsigns and diffview to point at. The `refs/worktree` namespace is per-worktree, like HEAD, so agents in linked worktrees never share a baseline.

Snapshots are built against an index of our own via `GIT_INDEX_FILE`, so `git add` never runs against the user's. It lives at `<git-dir>/codecompanion-index`, which puts it in the worktree's own directory for a linked worktree, and it's seeded by copying the user's index so git's stat cache spares us re-hashing every file. Anything wrong with it is fixed by discarding and rebuilding, because it's only ever a cache. Both sides of a diff are worktree snapshots produced the same way, which is what makes untracked files visible to a review while whatever the user has staged is ignored. `--ignore-errors` keeps a snapshot going past paths git can't index, such as a nested repo with no commit checked out.

This module also parses unified diff output into one entry per hunk, each with a content hash that stays stable until the change itself changes.

## Store

@./lua/codecompanion/interactions/code_review/store.lua

Everything persisted to disk, under the configured `storage_dir` and keyed by a flattened repo path, then by branch. It holds the pending comments as a markdown file the user can hand-edit, plus the sets tracking which files an agent edited, which hunks were accepted, and which files were ignored. `submit` writes the review out to a file for sharing with an agent outside of CodeCompanion.

## Diff

@./lua/codecompanion/interactions/code_review/diff.lua

Shows a single hunk against the baseline, either in Neovim's native diff or through the configured diff provider.

## UI

@./lua/codecompanion/interactions/code_review/ui.lua

Draws the pending comments into the buffers they were written against, as extmarks, and keeps them in step as files are opened or the comments file is edited. It only watches for buffers while there are comments left to draw.

## Keymaps

@./lua/codecompanion/interactions/code_review/keymaps.lua

Binds the review actions to the quickfix buffer, remembering what they replaced so they can be handed back. Because the quickfix list is shared, these check the review still owns the current list before acting.

## Editor context

@./lua/codecompanion/interactions/shared/editor_context/code_review.lua

How a review reaches an agent. This formats the pending comments into `<comment>` blocks and swaps them in for the `#{code_review}` tag, for both the chat buffer and the CLI interaction. It's the caller of `consume`, so sending a review is what advances the baseline.

## Commands

@./lua/codecompanion/commands/init.lua

`:CodeCompanionCodeReview` and its subcommands - `Accept`, `All`, `Approve`, `Comment`, `Comments`, `Ignore`.

## Config

@./lua/codecompanion/config.lua

Under `interactions.code_review`. Covers whether the feature is enabled, the storage directory, the diff provider, and the quickfix keymaps.

## Tests

@./tests/interactions/code_review/test_ui.lua
@./tests/interactions/code_review/test_store.lua
@./tests/interactions/code_review/test_baseline.lua
@./tests/interactions/code_review/test_code_review.lua

Mini.Test with child processes. Each case gets a fresh git repo and storage directory. Note that opening a file with a real extension pulls in filetype plugins and treesitter, so the cases use extension-less names where the filetype doesn't matter.

## Docs

@./doc/usage/code-review.md
@./doc/configuration/code-review.md
