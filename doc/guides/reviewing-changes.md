---
description: "Review the edits an LLM or agent has made in Neovim like a pull request, then accept, revert or comment on each one."
---

# Reviewing an Agent's Changes

An agent can change a dozen files in one turn, and reading them means hunting through your project and copying snippets back into the chat. CodeCompanion's _code review_ snapshots your project with git before the agent starts, then shows you everything that's changed since, hunk by hunk, like a pull request.

This page walks through the situations you'll review in. [Getting Started](/getting-started#reviewing-the-changes) covers the basics, and [Code Review](/usage/code-review) covers every feature.

> [!IMPORTANT]
> Code reviews are in **beta** and need your project to be a git repository

## After a Chat

You've asked the LLM to do something in the chat buffer and it's finished. Run:

```
:CodeCompanionCodeReview
```

A new tab opens. The _checklist_ on the left lists each changed file and its hunks, and the _review pane_ on the right shows the whole file with the changes highlighted. These keymaps are all you need to start:

| Keymap | Action |
| --- | --- |
| `ga` | Accept the hunk, or every hunk in the file when you're on a file row |
| `gr` | Revert the hunk, putting that part of the file back as it was |
| `gc` | Comment on the line under the cursor |
| `u` | Undo the last accept or revert |
| `i` / `I` | Edit the real file at this line, in the tab you came from |
| `?` | List every keymap |

Accepted and reverted hunks leave the checklist. When you want the LLM to act on your comments, go back to the chat and add `#{code_review}` to your message:

```md
#{code_review} Please address my comments
```

That closes the _round_. The next time you run `:CodeCompanionCodeReview`, you only see what the LLM changed in response. Clearing every hunk from the checklist and closing the tab also closes the round.

<p align="center">
<video controls muted title="Adding code review comments" src="https://github.com/user-attachments/assets/c4a1f997-6d94-4b37-a3ee-9dd553d5ee3c"></video>
</p>

### How Rounds Work

The snapshot is taken on the first message you send in a round. If you send more messages before reviewing, the snapshot stays put, so the review covers every edit since you last looked rather than just the latest turn.

Because the review is a diff between the snapshot and your files, it catches every change, whether it came from a tool, a shell command the agent ran, or your own typing. Each branch keeps its own snapshot, so switching branches doesn't mix reviews.

> [!NOTE]
> Snapshots use a git index owned by CodeCompanion, so your staged changes are never touched

## With an ACP Agent

Agents like Claude Code and Codex, used from the chat buffer over [ACP](/agent-client-protocol), work exactly as above. Sending a message takes the snapshot, and `#{code_review}` sends your comments. There's nothing to set up.

## With a CLI Agent

How changes are captured depends on where the agent runs.

### In CodeCompanion's CLI

If you run Claude Code through the [CLI interaction](/usage/cli), a prompt sent from Neovim, such as `:CodeCompanionCLI <prompt>`, takes the snapshot. A prompt you type straight into the terminal doesn't, unless you've installed CodeCompanion's hooks:

```
:CodeCompanionCLI Install
```

This adds hooks to `~/.claude/settings.json` that tell Neovim when each turn starts and ends. They only do anything when Claude Code was started by CodeCompanion. See [Hooks](/configuration/cli#hooks) for more.

Send your comments with `#{code_review}` in a CLI prompt, just as you would in the chat buffer.

### In a Separate Terminal

An agent that CodeCompanion didn't start, such as Claude Code in another terminal, can't tell Neovim when it begins work, so no snapshot is taken for it. For your first review, compare against the start of the branch instead:

```
:CodeCompanionCodeReview Branch
```

Leave your comments, then press `gs`. This writes them to a `review.md` file, copies its path to your clipboard and closes the round. Paste the path into the agent:

```
Please action my code review: /path/to/review.md
```

From then on, `:CodeCompanionCodeReview` only shows what the agent has changed since you shared.

> [!TIP]
> The `review.md` path never changes for a repository, so you can reference it in a `CLAUDE.md` or `AGENTS.md` file

## Commenting While You Read

You don't need the review window to leave a comment. If you're reading code in any buffer and spot something, put your cursor on the line, or select a range, and run:

```
:CodeCompanionCodeReview Comment
```

The comment shows as virtual text wherever the file is open, and is sent with the rest of your review. Run the same command on the same line to edit it. **Submitting a comment empty deletes it**.

## Before a Pull Request

A round only shows what changed since your last review. Before you open a pull request, read the whole branch in one pass, including uncommitted work:

```
:CodeCompanionCodeReview Branch
```

The branch is compared against where it left your default branch, which is taken from `origin/HEAD`, then `init.defaultBranch`, then `main` or `master`. Pending comments are kept. Once you've cleared the last hunk, reviews go back to following rounds.

## Listing Changed Files

To see which files were touched:

```
:CodeCompanionChat Changes
```

This opens the quickfix list with every file edited by CodeCompanion's tools or an ACP agent since Neovim started. It doesn't need git, but it doesn't see edits made by a CLI agent.

## Skipping Files

Lockfiles and generated files rarely need reading. To leave them out of every review, as if you'd accepted them:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      opts = {
        auto_accept = { "**/*.lock", "**/package-lock.json", "doc/**/*.txt" },
      },
    },
  },
})
```

Paths are relative to the repository root and follow `:h vim.glob`. The checklist header shows how many files were auto-accepted.

## Using Your Own Diff Viewer

The review always opens in its own tab. If you'd rather read the changes in another plugin, the snapshot is a normal git ref:

```
:DiffviewOpen refs/worktree/codecompanion/baseline
:Gitsigns change_base refs/worktree/codecompanion/baseline
```

You can still leave comments with `:CodeCompanionCodeReview Comment`, as long as you're in the working file rather than the baseline side of the diff. See [Configuring Code Reviews](/configuration/code-review) to change the keymaps, comment styling and storage location.

## Limitations

- Without git there's nothing to compare against, so `:CodeCompanionCodeReview` has nothing to show. Comments and `:CodeCompanionChat Changes` still work
- Files ignored by `.gitignore` never appear in a review. Neither do the contents of an embedded git repository or an uninitialised submodule, which are skipped
- The first snapshot in a large repository can pause Neovim while git indexes every file. Later snapshots reuse that index and are much quicker
- Comments are stored against line numbers, which drift if the file changes a lot before you send them. The code sent with each comment usually gives the LLM enough context
- Closing a round doesn't discard pending comments. Press `gC` in the review window to edit or delete them
