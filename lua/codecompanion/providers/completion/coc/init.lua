local M = {}

function M.init()
  return {
    priority = 9,
    shortcut = "CodeCompanion",
    filetypes = { "codecompanion" },
    triggerCharacters = { "/", "#", "@" },
  }
end

local completion = require("codecompanion.providers.completion")
local log = require("codecompanion.utils.log")

local callbacks = {}

---Converts CodeCompanion completion items to coc.nvim-compatible completion items.
---@param opt table Table containing completion trigger context (buffer info, input, cursor position).
---@param complete_items table Array of original CodeCompanion completion items.
---@return table Array of formatted completion items compatible with coc.nvim.
local function format_complete_items(opt, complete_items)
  for _, item in ipairs(complete_items) do
    --Set standard Vim completion-items fields (see :h complete-items).
    item.word = item.label:sub(2) --The text to insert after the trigger character.
    item.abbr = item.label --The text to show in the completion menu.
    item.info = item.detail --The details shown in the preview window.

    --Context to be used by CodeCompanion later.
    item.context = {
      bufnr = opt.bufnr,
      input = opt.input,
      cursor = { row = opt.linenr, col = opt.colnr },
    }

    --Store function pointers, as they are lost in serialization (replaced by vim.Nil).
    if item.config and type(item.config.callback) == "function" then
      callbacks[item.label] = item.config.callback
    end

    --Remove label; otherwise coc.nvim adds an extra trigger character.
    item.label = nil
  end

  return complete_items
end

---Provides CodeCompanion completion items for coc.nvim-triggered completion.
---@param opt table Completion trigger context
---@return table Completion items
function M.complete(opt)
  local complete_items

  if opt.triggerCharacter == "@" then
    complete_items = format_complete_items(opt, completion.tools())
  elseif opt.triggerCharacter == "#" then
    complete_items = format_complete_items(opt, completion.variables())
  elseif opt.triggerCharacter == "/" then
    complete_items = format_complete_items(opt, completion.slash_commands())
  else
    complete_items = {}
  end

  return complete_items
end

---Deletes text from the start position to the cursor position.
---@param bufnr number Buffer number
---@param start table Start position
---@param offset number
local function delete_text_to_cursor(bufnr, start, offset)
  local cursor = vim.api.nvim_win_get_cursor(0)

  -- Convert from 1-based to 0-based indices.
  local range = {
    start = {
      line = start.row - 1,
      character = start.col - 1 + offset,
    },
    ["end"] = {
      line = cursor[1] - 1,
      character = cursor[2], --Cursor end position is exclusive.
    },
  }

  vim.lsp.util.apply_text_edits({ { newText = "", range = range } }, bufnr, "utf-8")
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

  opt.label = opt.abbr --Necessary for command execution.
  opt.info = nil --No longer needed.

  --Restore the function callback.
  if opt.config and callbacks[opt.label] then
    opt.config.callback = callbacks[opt.label]
  end

  local chat = require("codecompanion").buf_get_chat(bufnr)

  completion.slash_commands_execute(opt, chat)
end

---Activates coc for the current buffer.
---@return nil
function M.ensure_buffer_attached()
  vim.b.coc_force_attach = true
end

---@type table The coc.nvim autoload file.
local autoload_file = {
  name = "codecompanion.vim",
  path = vim.fn.stdpath("config") .. "/autoload/coc/source",
  content = [[
function! coc#source#codecompanion#init() abort
  return v:lua.codecompanion_coc_init()
endfunction

function! coc#source#codecompanion#complete(opt, cb) abort
  return a:cb(v:lua.codecompanion_coc_complete(a:opt))
endfunction

function! coc#source#codecompanion#on_complete(opt) abort
  return a:cb(v:lua.codecompanion_coc_execute(a:opt))
endfunction
]],
}

---Ensures that the coc.nvim autoload file exists in the expected path.
---@return nil
function M.ensure_autoload_file()
  if vim.fn.filereadable(autoload_file.path) == 1 then
    return
  end
  vim.fn.mkdir(autoload_file.path, "p")
  local file_name = autoload_file.path .. "/" .. autoload_file.name
  local file = io.open(file_name, "w")
  if file then
    file:write(autoload_file.content)
    file:close()
  else
    return log:error("Failed to create coc source autoload file: " .. file_name)
  end
end

return M
