---
description: "Configure code reviews in CodeCompanion - comment styling, the review window's keymaps, and where reviews are stored."
---

# Configuring Code Reviews

> [!IMPORTANT]
> Code reviews are still in **beta**. As such, the workflow below is subject to change.

CodeCompanion enables users to undertake code reviews and easily share feedback with an agent. Find out how they work in the [usage guide](/usage/code-review).

## Disabling

To disable code reviews, set `enabled` to `false`:

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

Comments you haven't sent yet are shown as virtual text above the line they were left on. They can be configured with

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      display = {
        comments = {
          enabled = true, -- Show pending comments as virtual text in the buffer
          icon = "💬 ", -- The icon to use for a comment
          overflow = "trunc", -- See `:h nvim_buf_set_extmark` for `virt_lines_overflow`
        },
      },
    },
  },
})
```


## Editor Context

When you share a review with the [code_review](/usage/chat-buffer/editor-context#code-review) editor context, the tag itself is replaced in your message with a short phrase before it's sent. For example, the prompt:

```md
Can you action #{code_review}
```

Is replaced with:

```md
Can you action my comments from the code review, which I've attached
```

This can be changed with:

```lua
require("codecompanion").setup({
  interactions = {
    shared = {
      editor_context = {
        code_review = {
          opts = {
            replacement = "my comments from the code review, which I've attached",
          },
        },
      },
    },
  },
})
```

## Keymaps

Keymaps are bound solely to the review window's two panels. The default keymaps are:

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
          visible = false,
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

Pressing `?` in either panel lists the keymaps. Set `visible = false` to keep one out of that list.

To disable a keymap:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      keymaps = {
        -- Disable the share keymap
        share = false,
      },
    },
  },
})
```

## Storage Location

You can change the default storage location for code review assets with:

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
