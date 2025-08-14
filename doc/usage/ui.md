# User Interface

<p>
  <video muted controls loop src="https://github.com/user-attachments/assets/a37180a0-0f1b-4ffb-8fae-44669e9d3df7"></video>
</p>

CodeCompanion aims to keep any changes to the user's UI to a minimum. Aesthetics, especially in Neovim, are highly subjective. So whilst it won't set much by default, it does endeavour to allow users to hook into the plugin and customize the UI to their liking via [Events](events).

CodeCompanion exposes a global dictionary, `_G.codecompanion_chat_metadata` which users can leverage throughout their configuration. Using the chat buffer's buffer number as the key, the dictionary contains:

- `adapter` - The `name` and `model` of the chat buffer's current adapter
- `context_items` - The number of context items current in the chat buffer
- `cycles` - The number of cycles (User->LLM->User) that have taken place in the chat buffer
- `id` - The ID of the chat buffer
- `tokens` - The running total of tokens for the chat buffer
- `tools` - The number of tools in the chat buffer

You can also leverage `_G.codecompanion_current_context` to fetch the number of the buffer which the `#{buffer}` variable points at.

Below are some examples of how you can customize the UI related to CodeCompanion.

## Progress updates with Fidget.nvim by [@jessevdp](https://github.com/jessevdp)

<p align="center">
<video controls muted src="https://github.com/user-attachments/assets/f1419889-7b62-46f2-ba73-98327a1b378b"></video>
</p>

As per the discussion over at [#813](https://github.com/olimorris/codecompanion.nvim/discussions/813).

## Inline spinner with Fidget.nvim by [@yuhua99](https://github.com/yuhua99)

<p align="center">
<img src="https://github.com/user-attachments/assets/aafb706f-b04f-42e6-b58e-ad30366ee532" />
</p>

As per the comment on [#640](https://github.com/olimorris/codecompanion.nvim/discussions/640#discussioncomment-12866279).

## Status column extmarks with the inline assistant by [@lucobellic](https://github.com/lucobellic)

<p align="center">
  <img src="https://github.com/user-attachments/assets/1daa7409-414e-4f4c-91fe-cd9c3ed0640e" />
</p>

As per the discussion over at [#1297](https://github.com/olimorris/codecompanion.nvim/discussions/1297).

## Lualine.nvim integration

The plugin can be integrated with lualine.nvim to show an icon in the statusline when a request is being sent to an LLM:

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

## Heirline.nvim integration

The plugin can also be integrated into [heirline.nvim](https://github.com/rebelot/heirline.nvim) to show an icon when a request is being sent to an LLM and also to show useful meta information about the chat buffer.

In the video at the top of this page, you can see the fidget spinner alongside the heirline.nvim integration below:

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
