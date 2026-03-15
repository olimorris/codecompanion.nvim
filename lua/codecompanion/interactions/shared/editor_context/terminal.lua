local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.EditorContext.Terminal: CodeCompanion.EditorContext
local EditorContext = {}

---@param args CodeCompanion.EditorContextArgs
function EditorContext.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    buffer_context = args.buffer_context or (args.Chat and args.Chat.buffer_context),
    config = args.config,
    params = args.params,
    target = args.target,
  }, { __index = EditorContext })

  return self
end

local _terminal_data = {}

---Add the latest terminal output to the chat
---@return nil
function EditorContext:chat_render()
  local bufnr = _G.codecompanion_last_terminal
  if not bufnr then
    return log:warn("No recent terminal buffer found")
  end

  local start_line = 0
  if _terminal_data[bufnr] then
    start_line = _terminal_data[bufnr].lines - 3
  end

  local ok, content = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line, -1, false)
  if not ok then
    return log:warn("Failed to read terminal output")
  end

  _terminal_data[bufnr] = {
    lines = #content + (_terminal_data[bufnr] and _terminal_data[bufnr].lines or 0),
    timestamp = os.time(),
  }

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = fmt("Latest output from terminal buffer %d:\n\n````\n%s\n````", bufnr, table.concat(content, "\n")),
  }, { _meta = { source = "editor_context", tag = "terminal" }, visible = false })
end

---Return inline label and context block for the CLI interaction
---@return { inline: string, block: string }|nil
function EditorContext:cli_render()
  local bufnr = _G.codecompanion_last_terminal
  if not bufnr then
    log:warn("No recent terminal buffer found")
    return nil
  end

  local start_line = 0
  if _terminal_data[bufnr] then
    start_line = _terminal_data[bufnr].lines - 3
  end

  local ok, content = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line, -1, false)
  if not ok then
    log:warn("Failed to read terminal output")
    return nil
  end

  _terminal_data[bufnr] = {
    lines = #content + (_terminal_data[bufnr] and _terminal_data[bufnr].lines or 0),
    timestamp = os.time(),
  }

  return {
    inline = "the terminal output",
    block = fmt(
      [[- Latest terminal output:
````
%s
````
]],
      table.concat(content, "\n")
    ),
  }
end

return EditorContext
