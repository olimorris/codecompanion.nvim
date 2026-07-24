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

## Diff View

Pressing `d` on a hunk shows it as a diff against the baseline. Everything about that view lives under `opts.diff`:

```lua
require("codecompanion").setup({
  interactions = {
    code_review = {
      opts = {
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

If you don't wish to use the `native` provider, you can set a custom function. A function provider receives the hunk to render:

```lua
provider = function(target)
  -- target = { root, path, baseline_ref, line, id }
  vim.cmd("DiffviewOpen " .. target.baseline_ref .. " -- " .. target.path)
end,
```

`baseline_ref` is the stable `refs/worktree/codecompanion/baseline` alias, so the same value works with `gitsigns`, `diffview`, or any git-diff plugin.


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

