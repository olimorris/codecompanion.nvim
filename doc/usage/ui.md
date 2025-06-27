# User Interface

CodeCompanion aims to keep any changes to the user's UI to a minimum. Aesthetics, especially in Neovim, are highly subjective. So whilst it won't set much by default, it does endeavour to allow users to hook into the plugin and customize the UI to their liking via [Events](events).

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

The plugin can also be integrated into heirline.nvim to show an icon when a request is being sent to an LLM:

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
```
