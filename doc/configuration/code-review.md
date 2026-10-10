---
description: "Change how code review comments look, remap the review window's keymaps, auto-accept files and choose where reviews are stored."
---

# Configuring Code Reviews

> [!IMPORTANT]
> Code reviews are in **beta**, so the options below may change

_Code reviews_ let you step through an agent's changes, accept or revert them, and leave comments for it to address. See [Using Code Reviews](/usage/code-review) for the workflow.

## Disabling

Code reviews are enabled by default. To disable them:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      enabled = false,
    },
  },
})
```

## Comment Styling

Pending comments show as virtual text above the line they were left on:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      display = {
        comments = {
          enabled = true,
          icon = "💬 ",
          overflow = "trunc", -- See `:h nvim_buf_set_extmark` for `virt_lines_overflow`
        },
      },
    },
  },
})
```

## Editor Context

Before your message is sent, the [code_review](/usage/chat-buffer/editor-context#code-review) editor context is replaced with a short phrase, so `Can you action #{code_review}` becomes `Can you action my comments from the code review, which I've attached`. To change the phrase:

```lua
require("codecompanion").setup({
  interactions = {
    shared = {
      editor_context = {
        code_review = {
          opts = {
            replacement_message = "my comments from the code review, which I've attached",
          },
        },
      },
    },
  },
})
```

## Keymaps

Keymaps apply only to the review window's checklist and review pane. The defaults are:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      keymaps = {
        accept = {
          modes = { n = "ga" },
          callback = "accept",
          description = "Accept the hunk, or whole file, under the cursor",
        },
        revert = {
          modes = { n = "gr" },
          callback = "revert",
          description = "Revert the hunk under the cursor",
        },
        comment = {
          modes = { n = "gc" },
          callback = "comment",
          description = "Comment on the line under the cursor",
        },
        comments = {
          modes = { n = "gC" },
          callback = "comments",
          description = "Edit the pending comments by hand",
        },
        share = {
          modes = { n = "gs" },
          callback = "share",
          description = "Share comments for an agent outside of CodeCompanion",
        },
        undo = {
          modes = { n = "u" },
          callback = "undo",
          description = "Undo the last accept or revert",
        },
        edit = {
          modes = { n = { "i", "I" } },
          callback = "edit",
          description = "Edit the line in the file itself",
        },
        keymaps = {
          modes = { n = "?" },
          callback = "keymaps",
          description = "Show these keymaps",
          visible = false,
        },
        next_hunk = {
          modes = { n = "]h" },
          callback = "next_hunk",
          description = "Move to the next hunk",
        },
        previous_hunk = {
          modes = { n = "[h" },
          callback = "previous_hunk",
          description = "Move to the previous hunk",
        },
      },
    },
  },
})
```

`?` lists the keymaps in either panel. Set `visible = false` to leave one out of that list.

To disable a keymap, set it to `false`:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      keymaps = {
        share = false,
      },
    },
  },
})
```

## Auto-Accepting Files

Lockfiles, generated code and compiled docs rarely need reading. Files matching these globs are left out of the review window, as if you'd accepted them:

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

Paths are relative to the repository root. Globs follow `:h vim.glob`, so `*` stays within one directory and `**/` matches any depth.

## Storage Location

Pending comments are stored per repository and branch, alongside the `review.md` file that `gs` writes. To change where:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      opts = {
        storage_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "codecompanion", "code_review"),
      },
    },
  },
})
```
