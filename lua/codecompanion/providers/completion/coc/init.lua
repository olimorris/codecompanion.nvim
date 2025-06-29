--- @module 'coc'

local completion = require("codecompanion.providers.completion")

--- @type table Cache for callback addresses that get lost (replaced by vim.Nil) during serialization.
local callbacks_cache = {}

--- Transforms CodeCompanion completion items into coc.nvim-compatible completion items.
--- The completion items are modified in place!
--- @param opt table Trigger context from coc.nvim.
--- @param complete_items table CodeCompanion completion items.
--- @return table coc.nvim-compatible completion items.
local function transform_complete_items(opt, complete_items)
  for _, item in ipairs(complete_items) do
    -- Populate standard Vim completion-items fields (see :h complete-items).
    if opt.triggerCharacter == "#" then
      item.word = string.format("#{%s}", item.label:sub(2))
    elseif opt.triggerCharacter == "@" then
      item.word = string.format("@{%s}", item.label:sub(2))
    else
      item.word = item.label:sub(2)
    end
    item.abbr = item.label -- The text to show in the completion menu
    item.info = item.detail -- The details shown in the preview window

    -- Context to be used by CodeCompanion later
    item.context = {
      bufnr = opt.bufnr,
      input = opt.input,
      cursor = { row = opt.linenr, col = opt.colnr },
    }

    -- Cache callback function pointers.
    if item.config and type(item.config.callback) == "function" then
      callbacks_cache[item.label] = item.config.callback
    end

    -- Remove label; otherwise coc.nvim adds an extra trigger character.
    item.label = nil
  end

  return complete_items
end

--- Deletes text from the start position to the cursor position.
--- @param bufnr number Buffer number
--- @param start table Start position
--- @param start_offset number Start offset
local function delete_text_to_cursor(bufnr, start, start_offset)
  local cursor = vim.api.nvim_win_get_cursor(0)

  -- Convert from 1-based to 0-based indices.
  local range = {
    start = {
      line = start.row - 1,
      character = start.col - 1 + start_offset,
    },
    ["end"] = {
      line = cursor[1] - 1,
      character = cursor[2], -- Cursor end position is exclusive.
    },
  }

  vim.lsp.util.apply_text_edits({ { newText = "", range = range } }, bufnr, "utf-8")
end

--- @class coc.Source
local M = {}

---Returns coc.nvim source initialization parameters.
---@return table
function M.init()
  return {
    priority = 99,
    shortcut = "CodeCompanion",
    filetypes = { "codecompanion" },
    triggerCharacters = { "/", "#", "@" },
  }
end

---Provides CodeCompanion completion items for coc.nvim-triggered completion.
---@param opt table Completion trigger context
---@return table Completion items
function M.complete(opt)
  local complete_items

  if opt.triggerCharacter == "@" then
    complete_items = transform_complete_items(opt, completion.tools())
  elseif opt.triggerCharacter == "#" then
    complete_items = transform_complete_items(opt, completion.variables())
  elseif opt.triggerCharacter == "/" then
    complete_items = transform_complete_items(opt, completion.slash_commands())
  else
    complete_items = {}
  end

  return complete_items
end

---Executes selected slash command on coc.nvim-triggered completion action.
---@param opt table The selected item from the completion menu.
---@return nil
function M.execute(opt)
  if not (opt.type == "slash_command") then
    return
  end

  local bufnr = opt.context.bufnr

  -- Remove the keyword from the chat buffer.
  local start = opt.context.cursor
  delete_text_to_cursor(bufnr, start, -1)

  opt.label = opt.abbr -- Necessary for command execution
  opt.info = nil -- No longer needed

  -- Restore the function callback.
  if opt.config and callbacks_cache[opt.label] then
    opt.config.callback = callbacks_cache[opt.label]
  end

  local chat = require("codecompanion").buf_get_chat(bufnr)

  completion.slash_commands_execute(opt, chat)
end

return M
