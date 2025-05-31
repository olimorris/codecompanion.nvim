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

---Converts CodeCompanion completion items to CoC-compatible completion items.
---@param opt table Table containing completion trigger context (buffer info, input, cursor position).
---@param complete_items table Array of original CodeCompanion completion items.
---@return table Array of formatted completion items compatible with CoC.
local function format_complete_items(opt, complete_items)
  for _, item in ipairs(complete_items) do
    item.word = item.label:sub(2) --text to be inserted (after the trigger)
    item.abbr = item.label --text in the menu
    item.label = nil --messes up coc matching if set
    item.info = item.detail --information in preview window
    item.context = {
      bufnr = opt.bufnr,
      input = opt.input,
      cursor = { row = opt.linenr, col = opt.colnr },
    }
  end

  return complete_items
end

---Provides CodeCompanion completion items for CoC-triggered completion.
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

  -- convert from 1-based to 0-based
  local range = {
    start = {
      line = start.row - 1,
      character = start.col - 1 + offset,
    },
    ["end"] = {
      line = cursor[1] - 1,
      character = cursor[2], -- end position is exclusive
    },
  }

  vim.lsp.util.apply_text_edits({ { newText = "", range = range } }, bufnr, "utf-8")
end

---Executes selected slash command on CoC-triggered completion action.
---@param opt table The selected item from the completion menu.
---@return nil
function M.execute(opt)
  if not (opt.type == "slash_command") then
    return
  end

  local bufnr = opt.context.bufnr

  -- delete the keyword
  local start = opt.context.cursor
  delete_text_to_cursor(bufnr, start, -1)

  opt.label = opt.abbr --necessary for command execution
  opt.info = nil --not needed anymore

  local chat = require("codecompanion").buf_get_chat(bufnr)

  completion.slash_commands_execute(opt, chat)
end

---Activates coc for the current buffer.
---@return nil
function M.ensure_buffer_attached()
  vim.b.coc_force_attach = true
end

---@type table The CoC autoload file.
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

---Ensures that the CoC autoload file exists in the expected path.
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
    print("Failed to create coc source autoload file: " .. file_name)
  end
end

return M
