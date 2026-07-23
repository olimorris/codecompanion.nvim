# Code Review

CodeCompanion supports code reviews, based loosely on GitHub's pull requests. Find out how they work in the [usage guide](/usage/code-review).

## Enabling

By default, code reviews are disabled. To enable them:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      enabled = true,
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
