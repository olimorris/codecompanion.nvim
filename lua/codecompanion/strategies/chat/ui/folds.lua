local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local api = vim.api

---@class CodeCompanion.Chat.UI.Folds
local Folds = {}

local CONSTANTS = {
  NS_FOLD_TOOLS = api.nvim_create_namespace("CodeCompanion-tool_fold_marks"),
  NS_FOLD_CONTEXT = api.nvim_create_namespace("CodeCompanion-context_fold_marks"),
}

-- Unified fold summaries storage
-- fold_summaries[bufnr][start_line] = { content: string, type: string }
---@type table<integer, table<integer, { content: string, type: string }>>
Folds.fold_summaries = {}

---@class CodeCompanion.Chat.UI.FoldConfig
---@field type "tool"|"context"
---@field content string
---@field success_keywords? string[]
---@field failure_keywords? string[]

---Initialize fold settings for a buffer/window
---@param winnr integer
function Folds:setup(winnr)
  if winnr and api.nvim_win_is_valid(winnr) then
    api.nvim_win_call(winnr, function()
      if vim.wo.foldmethod ~= "manual" then
        vim.wo.foldmethod = "manual"
      end
    end)
    api.nvim_win_set_option(winnr, "foldtext", 'v:lua.require("codecompanion.strategies.chat.ui.folds").fold_text()')
  end
end

---Global method which Neovim calls to display folded text
---@return table
function Folds.fold_text()
  local bufnr = api.nvim_get_current_buf()
  local start = vim.v.foldstart - 1

  local folds = Folds.fold_summaries[bufnr] or {}
  local fold_data = folds[start]

  if not fold_data then
    -- Fallback for legacy data
    return Folds._format_fold_text("Unknown", "context")
  end

  return Folds._format_fold_text(fold_data.content, fold_data.type)
end

---Format fold text based on type
---@param content string
---@param fold_type "tool"|"context"
---@param opts? table
---@return table[]
function Folds._format_fold_text(content, fold_type, opts)
  opts = opts or {}
  local chunks = {}
  local icons = config.display.chat.icons

  if fold_type == "tool" then
    local icon_conf = icons.tool_success or ""
    local icon_hl = "CodeCompanionChatToolSuccessIcon"
    local summary_hl = "CodeCompanionChatToolSuccess"

    -- Check for failure keywords
    local failure_words = config.strategies.chat.tools.opts.folds.failure_words or {}
    for _, word in ipairs(failure_words) do
      if content:lower():find(word) then
        icon_conf = icons.tool_failure or ""
        icon_hl = "CodeCompanionChatToolFailureIcon"
        summary_hl = "CodeCompanionChatToolFailure"
        break
      end
    end

    table.insert(chunks, { icon_conf, icon_hl })
    if not opts.show_icon_only then
      table.insert(chunks, { content, summary_hl })
    end
  elseif fold_type == "context" then
    local icon = icons.chat_context or ""
    table.insert(chunks, { icon, "CodeCompanionChatContextIcon" })
    if not opts.show_icon_only then
      table.insert(chunks, { content, "CodeCompanionChatContext" })
    end
  end

  return chunks
end

---Delete a fold at the specified line
---@param bufnr integer
---@param line integer (0-based)
function Folds:_delete(bufnr, line)
  local success, err = pcall(function()
    api.nvim_buf_call(bufnr, function()
      local vim_line = line + 1
      local fold_start = vim.fn.foldclosed(vim_line)

      if fold_start ~= -1 then
        api.nvim_win_set_cursor(0, { fold_start, 0 })
        vim.cmd("normal! zd")

        -- Clean up stored data
        if self.fold_summaries[bufnr] then
          self.fold_summaries[bufnr][fold_start - 1] = nil
        end
      end
    end)
  end)

  if not success then
    log:trace("[Folds] Failed to delete fold at line %d: %s", line, err)
  end
end

---Create a new fold
---@param bufnr integer
---@param start_line integer (0-based)
---@param end_line integer (0-based)
---@param config CodeCompanion.Chat.UI.FoldConfig
function Folds:_create(bufnr, start_line, end_line, config)
  if start_line >= end_line then
    return
  end

  -- Store fold data with type information
  self.fold_summaries[bufnr] = self.fold_summaries[bufnr] or {}
  self.fold_summaries[bufnr][start_line] = {
    content = config.content,
    type = config.type,
  }

  local ns_to_use = config.type == "tool" and CONSTANTS.NS_FOLD_TOOLS or CONSTANTS.NS_FOLD_CONTEXT

  api.nvim_buf_set_extmark(bufnr, ns_to_use, start_line, 0, {
    virt_text = self._format_fold_text(config.content, config.type, { show_icon_only = true }),
    virt_text_pos = "inline",
    priority = 200,
  })

  -- Create the actual fold
  local success, err = pcall(function()
    api.nvim_buf_call(bufnr, function()
      vim.cmd(string.format("%d,%dfold", start_line + 1, end_line + 1))
    end)
  end)

  if not success then
    log:trace("[Folds] Failed to create %s fold: %s", config.type, err)
  end
end

---Create a fold by first deleting any existing folds in the range
---@param bufnr integer
---@param start_line integer (0-based)
---@param end_line integer (0-based)
---@param config CodeCompanion.Chat.UI.FoldConfig
function Folds:recreate(bufnr, start_line, end_line, config)
  -- Capture cursor position
  local cursor_pos
  api.nvim_buf_call(bufnr, function()
    cursor_pos = api.nvim_win_get_cursor(0)
  end)

  -- Clear extmarks for the range
  local ns = config.type == "tool" and CONSTANTS.NS_FOLD_TOOLS or CONSTANTS.NS_FOLD_CONTEXT
  api.nvim_buf_clear_namespace(bufnr, ns, start_line, end_line + 1)

  self:_delete(bufnr, start_line)
  self:_create(bufnr, start_line, end_line, config)

  -- Restore cursor position
  api.nvim_buf_call(bufnr, function()
    api.nvim_win_set_cursor(0, cursor_pos)
  end)
end

---Create a tool fold (backward compatibility method)
---@param bufnr integer
---@param start_line integer (0-based)
---@param end_line integer (0-based)
---@param foldtext string
function Folds:create_tool_fold(bufnr, start_line, end_line, foldtext)
  if not config.strategies.chat.tools.opts.folds.enabled then
    return
  end

  -- Don't fold single lines
  if start_line == end_line then
    -- Still add the extmark for visual indication
    api.nvim_buf_set_extmark(bufnr, CONSTANTS.NS_FOLD_TOOLS, start_line, 0, {
      virt_text = self._format_fold_text(foldtext, "tool", { show_icon_only = true }),
      virt_text_pos = "inline",
      priority = 200,
    })
    return
  end

  self:_create(bufnr, start_line, end_line, {
    type = "tool",
    content = foldtext,
  })
end

---Create a context fold (backward compatibility method)
---@param bufnr integer
---@param start_line integer (0-based)
---@param end_line integer (0-based)
---@param summary_text string
function Folds:create_context_fold(bufnr, start_line, end_line, summary_text)
  if not config.display.chat.fold_context then
    return
  end

  self:recreate(bufnr, start_line, end_line, {
    type = "context",
    content = summary_text,
  })
end

---Clean up fold data for a buffer
---@param bufnr integer
function Folds:cleanup(bufnr)
  if self.fold_summaries[bufnr] then
    self.fold_summaries[bufnr] = nil
  end

  -- Clear all extmarks
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_FOLD_TOOLS, 0, -1)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_FOLD_CONTEXT, 0, -1)
end

return Folds
