local config = require("codecompanion.config")

---@class CodeCompanion.Chat.UI.Tools
---@field chat_bufnr number The buffer number of the chat
---@field winnr number The window number of the chat
local Tools = {}

local api = vim.api
local tool_icons = config.display.chat.icons

local CONSTANTS = {
  NS_FOLD_TOOLS = api.nvim_create_namespace("CodeCompanion-tool_fold_marks"),
}

-- UI.fold_summaries[bufnr][start]   → the recorded line‐text for fold at 0-based row `start`
---@type table<integer, table<integer, string>>
Tools.fold_summaries = {}

---@param args CodeCompanion.Chat.UI.ToolArgs
function Tools.new(args)
  local self = setmetatable({
    chat_bufnr = args.chat_bufnr,
    winnr = args.winnr,
  }, { __index = Tools })

  self:setup_fold()

  return self
end

---Ensure that everytime we action a fold, we call this method
---@return nil
function Tools:setup_fold()
  api.nvim_win_set_option(
    self.winnr,
    "foldtext",
    'v:lua.require("codecompanion.strategies.chat.ui.tools").fold_tool_output()'
  )
end

---Format the tool output that will be displayed in the chat buffer
---@param content string The content from the tool
---@param opts? table Options for formatting
---@return table[]  list of {text, hl_group}
local function format_output(content, opts)
  opts = opts or {}

  local chunks = {}
  content = vim.trim(content)

  local icon_conf = tool_icons.tool_success or ""
  local icon_hl = "CodeCompanionChatToolSuccessIcon"
  local summary_hl = "CodeCompanionChatToolSuccess"

  for _, word in ipairs(config.strategies.chat.tools.opts.folds.failure_words) do
    if content:lower():find(word) then
      icon_conf = tool_icons.tool_failure or ""
      icon_hl = "CodeCompanionChatToolFailureIcon"
      summary_hl = "CodeCompanionChatToolFailure"
      break
    end
  end

  -- The first chunk is the icon, which is always shown
  table.insert(chunks, { icon_conf .. " ", icon_hl })

  if opts.show_icon_only then
    return chunks
  end

  -- The second chunk is the content of the tool output, if it exists
  table.insert(chunks, { content, summary_hl })

  return chunks
end

---Global method which Neovim calls to fold tool output
---@return table
function Tools.fold_output()
  local bufnr = api.nvim_get_current_buf()
  local start = vim.v.foldstart - 1

  local folds = Tools.fold_summaries[bufnr] or {}
  local lines = folds[start] or api.nvim_buf_get_lines(bufnr, start, start + 1, false)[1] or ""

  return format_output(lines)
end

---Create a fold with summary extmark in a single operation
---@param winnr number The window number where the fold should be applied
---@param bufnr number The buffer number where the fold should be applied
---@param start_row number The starting row of the fold (0-indexed)
---@param end_row number The ending row of the fold (0-indexed)
---@return nil
local function create_fold_with_summary(winnr, bufnr, start_row, end_row)
  local line = api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1] or ""
  api.nvim_buf_set_extmark(bufnr, CONSTANTS.NS_FOLD_TOOLS, start_row, 0, {
    virt_text = format_output(line, { show_icon_only = true }),
    virt_text_pos = "inline",
    priority = 200,
  })

  -- We only create a fold if there is more than one line
  if start_row < end_row then
    Tools.fold_summaries[bufnr] = Tools.fold_summaries[bufnr] or {}
    Tools.fold_summaries[bufnr][start_row] = line

    -- Make sure the fold method is set
    if winnr and api.nvim_win_is_valid(winnr) then
      api.nvim_win_call(winnr, function()
        if vim.wo.foldmethod ~= "manual" then
          vim.wo.foldmethod = "manual"
        end
      end)
    end

    -- And create the fold
    api.nvim_buf_call(bufnr, function()
      vim.cmd(string.format("%d,%dfold", start_row + 1, end_row + 1))
    end)
  end
end

---Start the folding of the tool output in the chat buffer
---@param opts? {start_line: number, is_error: boolean, offset: number}
---@return nil
function Tools:start_folding(opts)
  if not config.strategies.chat.tools.opts.folds.enabled then
    return
  end

  opts = opts or {}

  self.pending_fold = {
    start_line = opts.start_line or api.nvim_buf_line_count(self.chat_bufnr),
    is_error = opts.is_error or false,
    timestamp = vim.uv.hrtime(),
  }

  if opts.offset then
    self.pending_fold.start_line = self.pending_fold.start_line + opts.offset
  end
end

---Finish the folding of the tool output
---@return nil
function Tools:end_folding()
  if not config.strategies.chat.tools.opts.folds.enabled then
    return
  end
  local end_line = api.nvim_buf_line_count(self.chat_bufnr) - 1
  if self.pending_fold.start_line <= end_line then
    create_fold_with_summary(self.winnr, self.chat_bufnr, self.pending_fold.start_line, end_line)
  end
  self.pending_fold = nil
end

return Tools
