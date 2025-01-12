# Events / Hooks

In order to enable a tighter integration between CodeCompanion and your Neovim config, the plugin fires events at various points during its lifecycle.

## List of Events

The events that you can access are:

- `CodeCompanionChatOpened` - Fired after a chat has been opened
- `CodeCompanionChatClosed` - Fired after a chat has been closed
- `CodeCompanionChatAdapter` - Fired after the adapter has been set in the chat
- `CodeCompanionChatModel` - Fired after the model has been set in the chat
- `CodeCompanionChatPin` - Fired after a pinned reference has been updated in the messages table
- `CodeCompanionToolAdded` - Fired when a tool has been added to a chat
- `CodeCompanionAgentStarted` - Fired when an agent has been initiated in the chat
- `CodeCompanionAgentFinished` - Fired when an agent has finished all tool executions
- `CodeCompanionInlineStarted` - Fired at the start of the Inline strategy
- `CodeCompanionInlineFinished` - Fired at the end of the Inline strategy
- `CodeCompanionRequestStarted` - Fired at the start of any API request
- `CodeCompanionRequestFinished` - Fired at the end of any API request
- `CodeCompanionDiffAttached` - Fired when in Diff mode
- `CodeCompanionDiffDetached` - Fired when exiting Diff mode

## Consuming an Event

Events can be hooked into as follows:

```lua
local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionInline*",
  group = group,
  callback = function(request)
    if request.match == "CodeCompanionInlineFinished" then
      -- Format the buffer after the inline request has completed
      require("conform").format({ bufnr = request.buf })
    end
  end,
})
```

## Example: [Lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) integration

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

## Example: [Heirline.nvim](https://github.com/rebelot/heirline.nvim) integration

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
