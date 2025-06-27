local coc = require("codecompanion.providers.completion.coc")
local log = require("codecompanion.utils.log")

--coc.nvim currently requires new completion sources to be registered via a Vim autoload file.
---@type table Specifies autoload file properties for coc.nvim.
local autoload_file = {
  name = "codecompanion.vim",
  dir = vim.fn.stdpath("config") .. "/autoload/coc/source",
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

-- Expose coc.nvim completion event handlers.
_G.codecompanion_coc_init = coc.init
_G.codecompanion_coc_complete = coc.complete
_G.codecompanion_coc_execute = coc.execute

---Ensures that the coc.nvim autoload file exists in the expected path, creating it if missing.
---@return nil
local function ensure_autoload_file_exists()
  local dir = autoload_file.dir
  local path = dir .. "/" .. autoload_file.name

  -- Check if the file exists; if yes, do nothing.
  if vim.fn.filereadable(path) == 1 then
    return
  end

  -- Check if the directory exists; if no, create it.
  if vim.fn.isdirectory(dir) ~= 1 then
    if vim.fn.mkdir(dir, "p") ~= 1 then
      log:error("Failed to create coc source directory: " .. dir)
      return
    end
  end

  -- Open the file for writing.
  local file, err = io.open(path, "w")
  if not file then
    log:error('Failed to create coc source autoload file "' .. path .. '": ' .. err)
    return
  end

  -- Write the content and close.
  local ok, write_err = file:write(autoload_file.content)
  file:close()
  if not ok then
    log:error('Failed to write to coc source autoload file "' .. path .. '": ' .. write_err)
    return
  end
end

vim.api.nvim_create_autocmd("VimEnter", {
  callback = ensure_autoload_file_exists,
})

---Activates coc for the current buffer.
---@return nil
local function ensure_buffer_attached()
  vim.b.coc_force_attach = true
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "codecompanion",
  callback = ensure_buffer_attached,
})
