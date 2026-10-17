---
description: "Recipes for showing CodeCompanion's progress and chat metadata in Neovim with Fidget.nvim, lualine.nvim and heirline.nvim."
---

# Extending with UI Recipes

CodeCompanion fires [events](/usage/events) and exposes [chat metadata](/usage/ui) rather than changing your UI itself. These recipes, many from the community, use them to show progress and chat details in Neovim.

## Fidget.nvim Progress Updates

<p align="center">
<video controls muted title="Progress updates with Fidget.nvim" src="https://github.com/user-attachments/assets/f1419889-7b62-46f2-ba73-98327a1b378b"></video>
</p>

By [@jessevdp](https://github.com/jessevdp). See discussion [#813](https://github.com/olimorris/codecompanion.nvim/discussions/813) for the code.

## Fidget.nvim Inline Spinner

<p align="center">
<img src="https://github.com/user-attachments/assets/aafb706f-b04f-42e6-b58e-ad30366ee532" alt="Inline spinner" />
</p>

By [@yuhua99](https://github.com/yuhua99). See [this comment](https://github.com/olimorris/codecompanion.nvim/discussions/640#discussioncomment-12866279) on discussion #640 for the code.

## Status Column Extmarks

<p align="center">
  <img src="https://github.com/user-attachments/assets/1daa7409-414e-4f4c-91fe-cd9c3ed0640e" alt="Status column extmarks" />
</p>

By [@lucobellic](https://github.com/lucobellic), for the inline interaction. See discussion [#1297](https://github.com/olimorris/codecompanion.nvim/discussions/1297) for the code.

## Lualine.nvim

To show a spinner in [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) while a request is running:

```lua
local M = require("lualine.component"):extend()

M.processing = false
M.spinner_index = 1

local spinner_symbols = {
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
}
local spinner_symbols_len = 10

-- Initializer
function M:init(options)
  M.super.init(self, options)

  local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = "CodeCompanionRequest*",
    group = group,
    callback = function(request)
      if request.match == "CodeCompanionRequestStarted" then
        self.processing = true
      elseif request.match == "CodeCompanionRequestFinished" then
        self.processing = false
      end
    end,
  })
end

-- Function that runs every time statusline is updated
function M:update_status()
  if self.processing then
    self.spinner_index = (self.spinner_index % spinner_symbols_len) + 1
    return spinner_symbols[self.spinner_index]
  else
    return nil
  end
end

return M
```

## Heirline.nvim

The first video on this page shows this recipe alongside the Fidget.nvim progress updates. To show an icon in [heirline.nvim](https://github.com/rebelot/heirline.nvim) while a request is running, along with the buffer that `#{buffer}` shares and the chat's token and cycle counts:

```lua
local CodeCompanion = {
  static = {
    processing = false,
  },
  update = {
    "User",
    pattern = "CodeCompanionRequest*",
    callback = function(self, args)
      if args.match == "CodeCompanionRequestStarted" then
        self.processing = true
      elseif args.match == "CodeCompanionRequestFinished" then
        self.processing = false
      end
      vim.cmd("redrawstatus")
    end,
  },
  {
    condition = function(self)
      return self.processing
    end,
    provider = " ",
    hl = { fg = "yellow" },
  },
}

local IsCodeCompanion = function()
  return package.loaded.codecompanion and vim.bo.filetype == "codecompanion"
end

local CodeCompanionCurrentContext = {
  static = {
    enabled = true,
  },
  condition = function(self)
    return IsCodeCompanion() and _G.codecompanion_current_context ~= nil and self.enabled
  end,
  provider = function()
    local bufname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(_G.codecompanion_current_context), ":t")
    return "[  " .. bufname .. " ] "
  end,
  hl = { fg = "gray", bg = "bg" },
  update = {
    "User",
    pattern = { "CodeCompanionRequest*", "CodeCompanionContextChanged" },
    callback = vim.schedule_wrap(function(self, args)
      if args.match == "CodeCompanionRequestStarted" then
        self.enabled = false
      elseif args.match == "CodeCompanionRequestFinished" then
        self.enabled = true
      end
      vim.cmd("redrawstatus")
    end),
  },
}

local CodeCompanionStats = {
  condition = function(self)
    return IsCodeCompanion()
  end,
  static = {
    chat_values = {},
  },
  init = function(self)
    local bufnr = vim.api.nvim_get_current_buf()
    self.chat_values = _G.codecompanion_chat_metadata[bufnr]
  end,
  -- Tokens block
  {
    condition = function(self)
      return self.chat_values.tokens > 0
    end,
    RightSlantStart,
    {
      provider = function(self)
        return "   " .. self.chat_values.tokens .. " "
      end,
      hl = { fg = "gray", bg = "statusline_bg" },
      update = {
        "User",
        pattern = { "CodeCompanionChatOpened", "CodeCompanionRequestFinished" },
        callback = vim.schedule_wrap(function()
          vim.cmd("redrawstatus")
        end),
      },
    },
    RightSlantEnd,
  },
  -- Cycles block
  {
    condition = function(self)
      return self.chat_values.cycles > 0
    end,
    RightSlantStart,
    {
      provider = function(self)
        return "  " .. self.chat_values.cycles .. " "
      end,
      hl = { fg = "gray", bg = "statusline_bg" },
      update = {
        "User",
        pattern = { "CodeCompanionChatOpened", "CodeCompanionRequestFinished" },
        callback = vim.schedule_wrap(function()
          vim.cmd("redrawstatus")
        end),
      },
    },
    RightSlantEnd,
  },
}

```

`RightSlantStart` and `RightSlantEnd` are separator components from your own heirline.nvim config.
