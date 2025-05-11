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

local function get_completion_items(tbl)
  local result = {}
  for _, item in ipairs(tbl) do
    table.insert(result, {
      word = item.label:sub(2),
      abbr = item.label,
      info = item.detail,
    })
  end
  return result
end

function M.complete(opt)
  local result
  if opt.triggerCharacter == "@" then
    result = get_completion_items(completion.tools())
  elseif opt.triggerCharacter == "#" then
    result = get_completion_items(completion.variables())
  elseif opt.triggerCharacter == "/" then
    result = get_completion_items(completion.slash_commands())
  else
    result = {}
  end
  return result
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
