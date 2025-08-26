local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local api = vim.api

---@class CodeCompanion.Chat.UI.Folds
local Folds = {}

local CONSTANTS = {
  NS_FOLD_TOOLS = api.nvim_create_namespace("CodeCompanion-tool_fold_marks"),
  NS_FOLD_CONTEXT = api.nvim_create_namespace("CodeCompanion-context_fold_marks"),
  NS_FOLD_REASONING = api.nvim_create_namespace("CodeCompanion-reasoning_fold_marks"),
}

-- Unified fold summaries storage
---@type table<number, table<number, { content: string, type: "tool"|"context"|"reasoning" }>>
Folds.fold_summaries = {}

---@class CodeCompanion.Chat.UI.FoldConfig
---@field type "tool"|"context"|"reasoning"
---@field content string
---@field success_keywords? string[]
---@field failure_keywords? string[]

---Initialize fold settings for a buffer/window
---@param winnr number
function Folds:setup(winnr)
  if winnr and api.nvim_win_is_valid(winnr) then
    api.nvim_win_call(winnr, function()
      if vim.wo.foldmethod ~= "manual" then
        vim.wo.foldmethod = "manual"
      end
    end)
    api.nvim_set_option_value(
      "foldtext",
      'v:lua.require("codecompanion.strategies.chat.ui.folds").fold_text()',
      { win = winnr }
    )
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
---@param fold_type "tool"|"context"|"reasoning"
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
  elseif fold_type == "reasoning" then
    table.insert(chunks, { content, "CodeCompanionChatFold" })
  end

  return chunks
end

---Delete a fold exactly at the specified line, without affecting outer folds
---@param bufnr number
---@param line number  -- 0-based start line of the exact fold to remove
function Folds:_delete(bufnr, line)
  local ok, err = pcall(function()
    api.nvim_buf_call(bufnr, function()
      local lnum = line + 1

      -- Ensure outer folds are open so we don't target a parent fold
      vim.fn.cursor(lnum, 1)
      vim.cmd("normal! zv")

      -- If the target fold is open, close just that fold at its start
      if vim.fn.foldclosed(lnum) == -1 then
        vim.cmd("normal! zc")
      end

      -- Now delete exactly one fold at this line (if present)
      if vim.fn.foldclosed(lnum) ~= -1 then
        vim.cmd("normal! zd")
      end

      -- Keep our summaries in sync
      if Folds.fold_summaries[bufnr] then
        Folds.fold_summaries[bufnr][line] = nil
      end
    end)
  end)
  if not ok then
    log:trace("[Folds] Failed to delete exact fold at line %d: %s", line, err)
  end
end

---Create a new fold
---@param bufnr number
---@param start_row number (0-based)
---@param end_row number (0-based)
---@param fold_config CodeCompanion.Chat.UI.FoldConfig
function Folds:_create(bufnr, start_row, end_row, fold_config)
  if start_row >= end_row then
    return
  end

  -- Store fold data with type information
  self.fold_summaries[bufnr] = self.fold_summaries[bufnr] or {}
  self.fold_summaries[bufnr][start_row] = {
    content = fold_config.content,
    type = fold_config.type,
  }

  -- Only add inline extmarks for tool/context. Reasoning gets no extmarks.
  local ns_to_use = nil
  if fold_config.type == "tool" then
    ns_to_use = CONSTANTS.NS_FOLD_TOOLS
  elseif fold_config.type == "context" then
    ns_to_use = CONSTANTS.NS_FOLD_CONTEXT
  end

  if ns_to_use then
    api.nvim_buf_set_extmark(bufnr, ns_to_use, start_row, 0, {
      virt_text = self._format_fold_text(fold_config.content or "", fold_config.type, { show_icon_only = true }),
      virt_text_pos = "inline",
      priority = 200,
    })
  end

  local ok, err = pcall(function()
    api.nvim_buf_call(bufnr, function()
      vim.cmd(string.format("%d,%dfold", start_row + 1, end_row + 1))
    end)
  end)
  if not ok then
    log:trace("[Folds] Failed to create %s fold: %s", fold_config.type, err)
  end
end

---Create a fold by deleting any existing folds in the range and recreating
---@param bufnr number
---@param start_row number (0-based)
---@param end_row number (0-based)
---@param fold_config CodeCompanion.Chat.UI.FoldConfig
function Folds:recreate(bufnr, start_row, end_row, fold_config)
  local cursor_pos
  api.nvim_buf_call(bufnr, function()
    cursor_pos = api.nvim_win_get_cursor(0)
  end)

  local ns = nil
  if fold_config.type == "tool" then
    ns = CONSTANTS.NS_FOLD_TOOLS
  elseif fold_config.type == "context" then
    ns = CONSTANTS.NS_FOLD_CONTEXT
  elseif fold_config.type == "reasoning" then
    ns = CONSTANTS.NS_FOLD_REASONING
  end
  if ns then
    api.nvim_buf_clear_namespace(bufnr, ns, start_row, end_row + 1)
  end

  self:_delete(bufnr, start_row)
  self:_create(bufnr, start_row, end_row, fold_config)

  api.nvim_buf_call(bufnr, function()
    api.nvim_win_set_cursor(0, cursor_pos)
  end)
end

---Create a tool fold (backward compatibility method)
---@param bufnr number
---@param start_row number (0-based)
---@param end_row number (0-based)
---@param foldtext string
function Folds:create_tool_fold(bufnr, start_row, end_row, foldtext)
  if not config.strategies.chat.tools.opts.folds.enabled then
    return
  end

  -- Don't fold single lines
  if start_row == end_row then
    -- Still add the extmark for visual indication
    api.nvim_buf_set_extmark(bufnr, CONSTANTS.NS_FOLD_TOOLS, start_row, 0, {
      virt_text = self._format_fold_text(foldtext, "tool", { show_icon_only = true }),
      virt_text_pos = "inline",
      priority = 200,
    })
    return
  end

  self:_create(bufnr, start_row, end_row, {
    type = "tool",
    content = foldtext,
  })
end

---Create a context fold (backward compatibility method)
---@param bufnr number
---@param start_row number (0-based)
---@param end_row number (0-based)
---@param summary_text string
function Folds:create_context_fold(bufnr, start_row, end_row, summary_text)
  if not config.display.chat.fold_context then
    return
  end

  self:recreate(bufnr, start_row, end_row, {
    type = "context",
    content = summary_text,
  })
end

---Fold the most recent reasoning section in the chat buffer
---@param chat CodeCompanion.Chat
---@param start_row number (0-based)
---@param end_row number (0-based)
---@return nil
function Folds:create_reasoning_fold(chat, start_row, end_row)
  if not config.display.chat.fold_reasoning then
    return
  end

  local summary_text = "  " .. config.display.chat.icons.chat_fold .. " ..."

  local bufnr = chat.bufnr
  local parser = chat.parser
  if not (bufnr and parser) then
    return
  end

  local ok, query = pcall(
    vim.treesitter.query.parse,
    "markdown",
    [[
    (section
      (atx_heading
        (atx_h3_marker)
        heading_content: (_) @block_name
      )
      (#eq? @block_name "Reasoning")
    ) @reasoning
  ]]
  )
  if not ok or not query then
    return
  end

  local tree = parser:parse({ start_row, end_row })[1]
  if not tree then
    return
  end
  local root = tree:root()

  local latest_node, latest_range = nil, -1
  for id, node in query:iter_captures(root, bufnr, start_row, end_row) do
    if query.captures[id] == "reasoning" then
      local range = node:range()
      if range >= latest_range then
        latest_node, latest_range = node, range
      end
    end
  end
  if not latest_node then
    return
  end

  local range, _, er = latest_node:range()
  local fold_start = range + 1
  local fold_end = math.max(fold_start, er - 1)

  -- Don't fold if there's no content to fold
  if fold_start >= fold_end then
    return
  end

  self:recreate(bufnr, fold_start, fold_end, {
    type = "reasoning",
    content = summary_text,
  })
end

---Clean up fold data for a buffer
---@param bufnr number
function Folds:cleanup(bufnr)
  if self.fold_summaries[bufnr] then
    self.fold_summaries[bufnr] = nil
  end

  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_FOLD_TOOLS, 0, -1)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_FOLD_CONTEXT, 0, -1)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_FOLD_REASONING, 0, -1)
end

return Folds
