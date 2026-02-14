--[[
===============================================================================
    File:       codecompanion.interactions/inline/completion.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      This module provides some helper functions for the Neovim 0.12+ feature
      of inline completions. It allows users to accept inline completions
      by extracting the next word or line from the completion text.

      Inspired by Copilot.lua's equivalent functionality.
      Use at your own risk. Not supported by the CodeCompanion project.

      This code is licensed under the Apache-2.0 License.
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
--]]

local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

---Extract the next word from text starting at the beginning
---Uses the same pattern as Copilot.lua
---@param text string The completion text
---@return string|nil word The extracted word, or nil if no word found
local function extract_next_word(text)
  -- Pattern matches: optional whitespace + optional punctuation + word chars + optional trailing whitespace
  -- %s* = zero or more whitespace
  -- %p* = zero or more punctuation
  -- [^%s%p]* = zero or more non-whitespace, non-punctuation chars (the actual word)
  -- %s* = zero or more trailing whitespace
  local _, end_pos = string.find(text, "^%s*%p*[^%s%p]*%s*")
  if end_pos then
    return string.sub(text, 1, end_pos)
  end
  return nil
end

---Extract text up to and including the next newline
---@param text string The completion text
---@return string|nil line The extracted line, or nil if empty
local function extract_next_line(text)
  if not text or text == "" then
    return nil
  end

  local newline_pos = string.find(text, "\n")

  if not newline_pos then
    return text
  end

  -- If text starts with newline, find the NEXT newline to get actual content
  if newline_pos == 1 then
    local second_newline = string.find(text, "\n", 2)
    if second_newline then
      return string.sub(text, 1, second_newline)
    end
    return text
  end

  return string.sub(text, 1, newline_pos)
end

---Validate that cursor is within the completion range
---@param item table The completion item
---@param cursor_row number The current cursor row (0-indexed)
---@param cursor_col number The current cursor column (0-indexed)
---@return boolean valid Whether the completion is valid
local function validate_completion(item, cursor_row, cursor_col)
  if not item.range then
    return true
  end

  local start_row = item.range.start.row
  local start_col = item.range.start.col
  local end_row = item.range.end_.row
  local end_col = item.range.end_.col

  -- Allow cursor anywhere within range to support auto-pairs
  if cursor_row < start_row or cursor_row > end_row then
    return false
  end
  if cursor_row == start_row and cursor_col < start_col then
    return false
  end
  if cursor_row == end_row and cursor_col > end_col then
    return false
  end

  return true
end

---Extract the insert text from the completion item
---@param item table The completion item
---@return string|nil text The insert text, or nil if invalid
local function get_insert_text(item)
  local text = item.insert_text

  if type(text) ~= "string" then
    if type(text) == "table" and text.value then
      return text.value
    else
      log:warn("Unexpected insert_text type: %s", type(text))
      return nil
    end
  end

  return text
end

---Get the new text by removing the existing buffer text prefix
---@param item table The completion item
---@param text string The full completion text
---@param cursor_row number The current cursor row (0-indexed)
---@param cursor_col number The current cursor column (0-indexed)
---@return string new_text The text after removing existing prefix
local function get_new_text(item, text, cursor_row, cursor_col)
  local bufnr = api.nvim_get_current_buf()
  local start_row = item.range.start.row
  local start_col = item.range.start.col

  -- Use cursor position instead of range.end_ to handle auto-pairs
  local existing_lines = api.nvim_buf_get_text(bufnr, start_row, start_col, cursor_row, cursor_col, {})
  local existing_text = table.concat(existing_lines, "\n")

  if vim.startswith(text, existing_text) then
    return text:sub(#existing_text + 1)
  else
    return text
  end
end

---Insert text at cursor (replacing to range end) and move cursor to the end
---@param text string The text to insert
---@param cursor_row number The current cursor row (0-indexed)
---@param cursor_col number The current cursor column (0-indexed)
---@param end_row number The range end row (0-indexed)
---@param end_col number The range end column (0-indexed)
local function insert_and_move_cursor(text, cursor_row, cursor_col, end_row, end_col)
  local lines = vim.split(text, "\n", { plain = true })
  api.nvim_buf_set_text(0, cursor_row, cursor_col, end_row, end_col, lines)

  -- Move cursor to the end of the inserted text
  local new_row, new_col
  if #lines > 1 then
    -- Multiple lines: move to the end of the last line
    new_row = cursor_row + #lines - 1
    new_col = #lines[#lines]
  else
    -- Single line: move to the end of the inserted text
    new_row = cursor_row
    new_col = cursor_col + #lines[1]
  end
  api.nvim_win_set_cursor(0, { new_row + 1, new_col })

  log:trace("Inserted %d chars, %d lines", #text, #lines)
end

---Generic function to accept partial completion
---@param extract_fn function Function to extract the desired portion of text
---@return boolean success Whether text was accepted
local function accept_partial(extract_fn)
  local accepted = false

  vim.lsp.inline_completion.get({
    on_accept = function(item)
      local cursor = api.nvim_win_get_cursor(0)
      local cursor_row = cursor[1] - 1 -- Convert to 0-indexed
      local cursor_col = cursor[2]

      if not validate_completion(item, cursor_row, cursor_col) then
        return
      end

      local text = get_insert_text(item)
      if not text then
        return
      end

      local new_text = get_new_text(item, text, cursor_row, cursor_col)

      local extracted = extract_fn(new_text)
      if not extracted then
        log:debug("No text could be extracted from completion")
        return
      end

      local end_row = item.range.end_.row
      local end_col = item.range.end_.col
      insert_and_move_cursor(extracted, cursor_row, cursor_col, end_row, end_col)
      accepted = true
    end,
  })

  return accepted
end

---Accept the next word from the current inline completion
---@return boolean success Whether a word was accepted
function M.accept_word()
  return accept_partial(extract_next_word)
end

---Accept the next line from the current inline completion
---@return boolean success Whether a line was accepted
function M.accept_line()
  return accept_partial(extract_next_line)
end

return M
