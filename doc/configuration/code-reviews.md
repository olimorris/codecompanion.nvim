# Configuring Code Reviews

CodeCompanion supports code reviews, based loosely on GitHub's pull requests. Find out how they work in the [usage guide](/usage/code-reviews).

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

