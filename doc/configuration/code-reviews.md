---
description: "Configure code reviews in CodeCompanion - comment styling, the diff view and its providers, quickfix keymaps, and where reviews are stored."
---

# Configuring Code Reviews

CodeCompanion enables users to undertake code reviews and easily share feedback with an agent. Find out how they work in the [usage guide](/usage/code-reviews).

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
        virtual_text = {
          enabled = true, -- Show pending comments as virtual text in the buffer
          icon = "💬 ", -- The icon to use for virtual text
          overflow = "trunc", -- See `:h nvim_buf_set_extmark` for `virt_lines_overflow`
        },
      },
    },
  },
})
```


## Diff View

Pressing `d` on a quickfix entry shows it as a diff against the baseline. The diff can be configurd with:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      display = {
        diff = {
          enabled = true, -- Set to false to render nothing, especially if you're using your own provider
          layout = "vertical", -- vertical or horizontal
          provider = "native", -- "native": Neovim's own diff (default), or a function to render the hunk yourself
        },
      },
    },
  },
})
```

If you don't wish to use the `native` Neovim provider, you can set a custom function. A function provider receives the hunk to render:

```lua
provider = function(target)
  -- target = { root, path, baseline_ref, line, id }
  vim.cmd("DiffviewOpen " .. target.baseline_ref .. " -- " .. target.path)
end,
```

`baseline_ref` is the stable `refs/worktree/codecompanion/baseline` alias, so the same value works with `gitsigns`, `diffview`, or any git-diff plugin.

> [!TIP]
> The native provider does not touch your `diffopt` config

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

Keymaps are bound solely to the code review's quickfix window. The default keymaps are:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      keymaps = {
        accept = {
          modes = { n = "a" },
          callback = "keymaps.accept",
          description = "Accept the hunk under the cursor",
        },
        comment = {
          modes = { n = "c" },
          callback = "keymaps.comment",
          description = "Comment on the hunk under the cursor",
        },
        diff = {
          modes = { n = "d" },
          callback = "keymaps.diff",
          description = "Diff the hunk under the cursor against the baseline",
        },
        ignore = {
          modes = { n = "x" },
          callback = "keymaps.ignore",
          description = "Ignore the hunk's file until the baseline advances",
        },
      },
    },
  },
})
```

To disable a keymap:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      keymaps = {
        -- Disable the ignore keymap
        ignore = false,
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
