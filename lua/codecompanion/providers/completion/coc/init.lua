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

local function format_complete_items(opt, complete_items)
  for _, item in ipairs(complete_items) do
    item.word = item.label:sub(2)
    item.abbr = item.label
    item.label = nil -- necessary for coc matching
    item.info = item.detail
    item.context = {
      bufnr = opt.bufnr,
      input = opt.input,
      cursor = { row = opt.linenr, col = opt.colnr },
    }
  end
  return complete_items
end

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

function M.execute(opt)
  if not (opt.type == "slash_command") then
    return
  end
  opt.label = opt.abbr -- necessary for command execution
  local chat = require("codecompanion").buf_get_chat(opt.context.bufnr)
  completion.slash_commands_execute(opt, chat)
end

-- Activates coc for a non-attached buffer.
function M.ensure_buffer_attached()
  vim.b.coc_force_attach = true
end

-- NOTE: The only way to register a new coc completion source is currently by creating an autoload file in the given path. This shall change in the future!
local autoload_file = {
  name = "codecompanion.vim",
  path = vim.fn.expand("~/.vim/autoload/coc/source"),
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
