local api = vim.api

local M = {}

---Get the visible lines in all visible buffers
---@return table
function M.get_visible_lines()
  local lines = {}
  local wins = vim.api.nvim_list_wins()

  for _, win in ipairs(wins) do
    local bufnr = vim.api.nvim_win_get_buf(win)

    if vim.api.nvim_get_option_value("filetype", { buf = bufnr }) ~= "codecompanion" then
      local start_line = vim.api.nvim_win_call(win, function()
        return vim.fn.line("w0")
      end)
      local end_line = vim.api.nvim_win_call(win, function()
        return vim.fn.line("w$")
      end)

      if not lines[bufnr] then
        lines[bufnr] = {}
      end

      table.insert(lines[bufnr], { start_line, end_line })
    end
  end

  return lines
end

---Get the relative name of a buffer from the buffer number
---@param bufnr number
---@return table
function M.name_from_bufnr(bufnr)
  local bufname = api.nvim_buf_get_name(bufnr)
  if vim.fn.has("win32") == 1 then
    -- On Windows, slashes need to be consistent with getcwd, which uses backslashes
    bufname = bufname:gsub("/", "\\")
  end
  return vim.fn.fnamemodify(bufname, ":.")
end

---Get the information of a given buffer
---@param bufnr number
---@return table
function M.get_info(bufnr)
  local bufname = api.nvim_buf_get_name(bufnr)
  local relative_path = vim.fn.fnamemodify(bufname, ":.")

  return {
    bufnr = bufnr,
    filetype = api.nvim_buf_get_option(bufnr, "filetype"),
    number = bufnr,
    name = vim.fn.fnamemodify(bufname, ":t"),
    path = bufname,
    short_path = vim.fn.fnamemodify(bufname, ":h:t") .. "/" .. vim.fn.fnamemodify(bufname, ":t"),
    relative_path = relative_path,
  }
end

---Return metadata on all of the currently valid and loaded buffers
---@param ft? string The filetype to filter the buffers by
---@return {name: string, bufnr: number, filetype: string, path: string, relative_path: string}[]
function M.get_open(ft)
  local buffers = {}

  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      table.insert(buffers, M.get_info(bufnr))
    end
  end

  -- Filter by filetype if needed
  if ft then
    buffers = vim.tbl_filter(function(buf)
      return buf.filetype == ft
    end, buffers)
  end

  return buffers
end

---Check if a path is open as a buffer and return the buffer number
---@param path string The path to check
---@return number|nil Buffer number if found, nil otherwise
function M.get_bufnr_from_path(path)
  local normalized_path = vim.fn.fnamemodify(path, ":p")

  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      local buf_path = vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ":p")
      if buf_path == normalized_path then
        return bufnr
      end
    end
  end

  return nil
end

---Get the content of a given buffer
---@param bufnr number
---@param range? table
---@return string
function M.get_content(bufnr, range)
  range = range or { 0, -1 }

  local lines = api.nvim_buf_get_lines(bufnr, range[1], range[2], false)
  local content = table.concat(lines, "\n")

  return content
end

---Add line numbers to the table of content
---@param content string
---@return string
function M.add_line_numbers(content)
  local formatted = {}

  content = vim.split(content, "\n")
  for i, line in ipairs(content) do
    table.insert(formatted, string.format("%d:  %s", i, line))
  end

  return table.concat(formatted, "\n")
end

---Write content to a given buffer
---@param bufnr number
---@param content string|table
---@return boolean, string|nil
function M.write(bufnr, content)
  local old = {
    modifiable = vim.bo[bufnr].modifiable,
    readonly = vim.bo[bufnr].readonly,
  }
  if not old.modifiable then
    vim.bo[bufnr].modifiable = true
  end
  if old.readonly then
    vim.bo[bufnr].readonly = false
  end

  local lines = content
  if type(lines) == "string" then
    lines = vim.split(content or "", "\n", { plain = true })
  end

  api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

  api.nvim_buf_call(bufnr, function()
    vim.cmd("silent update!")
  end)

  if not old.modifiable then
    vim.bo[bufnr].modifiable = false
  end
  if old.readonly then
    vim.bo[bufnr].readonly = true
  end

  return true
end

return M
