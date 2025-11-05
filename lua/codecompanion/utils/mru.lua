local api = vim.api
local inspect = vim.inspect

local M = {}

local mru = {}

local initialized = false

local function push(bufnr)
  if not bufnr or bufnr == 0 then
    return
  end
  if not api.nvim_buf_is_valid(bufnr) or not vim.bo[bufnr].buflisted then
    return
  end
  for i = #mru, 1, -1 do
    if mru[i] == bufnr then
      table.remove(mru, i)
    end
  end
  table.insert(mru, bufnr)
end

local function remove(bufnr)
  for i = #mru, 1, -1 do
    if mru[i] == bufnr then
      table.remove(mru, i)
    end
  end
end

local function top(n)
  n = n or 1
  return mru[#mru - (n - 1)]
end

local push_events = { "BufEnter", "BufWinEnter", "WinEnter", "TabEnter", "BufAdd" }
local remove_events = { "BufDelete", "BufWipeout", "BufUnload" }

local function register_autocmds()
  api.nvim_create_autocmd(push_events, {
    pattern = "*",
    callback = function(ev)
      local bufnr = ev and ev.buf or api.nvim_get_current_buf()
      pcall(function() push(bufnr) end)
    end,
  })

  api.nvim_create_autocmd(remove_events, {
    pattern = "*",
    callback = function(ev)
      local bufnr = ev and ev.buf
      if bufnr then
        pcall(function() remove(bufnr) end)
      end
    end,
  })
end

local function find_mru_file_buffer(opts)
  opts = opts or {}
  local excluded_filetypes = {
    "codecompanion",
    "help",
    "terminal",
    "prompt",
    "packer",
    "fugitive",
  }

  local excluded_buftypes = { "nofile" }

  local cur = api.nvim_get_current_buf()
  for i = #mru, 1, -1 do
    local bufnr = mru[i]

    if api.nvim_buf_is_valid(bufnr) and bufnr ~= cur and vim.bo[bufnr].buflisted then
      local name = vim.api.nvim_buf_get_name(bufnr) or ""
      local ft = vim.bo[bufnr].filetype or ""
      local btype = vim.bo[bufnr].buftype or ""

      if vim.tbl_contains(excluded_filetypes, ft) then
        goto continue
      end
      if vim.tbl_contains(excluded_buftypes, btype) then
        goto continue
      end

      if btype == "" and name ~= "" then
        return bufnr
      end
    else
      if not api.nvim_buf_is_valid(bufnr) or not vim.bo[bufnr].buflisted then
        table.remove(mru, i)
      end
    end
    ::continue::
  end

  return cur
end

local function refresh()
  mru = {}
  pcall(function()
    local all = vim.fn.getbufinfo({ buflisted = 1 }) or {}
    table.sort(all, function(a, b)
      if a.lastused and b.lastused then
        return a.lastused > b.lastused
      end
      return (a.bufnr or 0) > (b.bufnr or 0)
    end)
    for _, info in ipairs(all) do
      if info and info.bufnr then
        table.insert(mru, info.bufnr)
      end
    end
  end)
end

---Register MRU autocmds and seed the MRU list.
---Safe to call multiple times; registration happens once.
function M.setup()
  if initialized then
    return
  end
  initialized = true

  -- Seed MRU from existing buffers
  pcall(function()
    local all = vim.fn.getbufinfo({ buflisted = 1 }) or {}
    table.sort(all, function(a, b)
      if a.lastused and b.lastused then
        return a.lastused > b.lastused
      end
      return (a.bufnr or 0) > (b.bufnr or 0)
    end)
    for _, info in ipairs(all) do
      if info and info.bufnr then
        table.insert(mru, info.bufnr)
      end
    end
  end)

  register_autocmds()
end

local function debug()
  pcall(function()
    vim.api.nvim_out_write("MRU: " .. inspect(mru) .. "\n")
  end)
end

M.push = push
M.remove = remove
M.top = top
M.find_mru_file_buffer = find_mru_file_buffer
M.refresh = refresh
M.debug = debug

return M
