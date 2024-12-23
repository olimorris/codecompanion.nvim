local api = vim.api

local M = {}

---Get the visible lines in all visible buffers
---@return table
function M.get_visible_lines()
  local lines = {}
  local wins = vim.api.nvim_list_wins()

  for _, win in ipairs(wins) do
    local bufnr = vim.api.nvim_win_get_buf(win)

    if not buf.is_codecompanion_buffer(bufnr) then
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

---Get the information of a given buffer
---@param bufnr number
---@return table
function M.get_info(bufnr)
  local bufname = api.nvim_buf_get_name(bufnr)
  local relative_path = vim.fn.fnamemodify(bufname, ":.")

  return {
    bufnr = bufnr,
    filetype = api.nvim_buf_get_option(bufnr, "filetype"),
    id = bufnr,
    name = vim.fn.fnamemodify(bufname, ":t"),
    path = bufname,
    relative_path = relative_path,
  }
end

---Return metadata on all of the currently valid and loaded buffers
---@param ft? string The filetype to filter the buffers by
---@return table
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

---Get the content of a given line in a buffer
---@param bufnr number
---@param line number
---@return string
function M.get_line(bufnr, line)
  return api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
end

---Formats the content of a buffer into a markdown string
---@param buffer table The buffer data to include
---@param lines string The lines of the buffer to include
---@return string
local function format(buffer, lines)
  lines = vim.split(lines, "\n")
  local formatted = {}
  for i, line in ipairs(lines) do
    table.insert(formatted, string.format("%d:  %s", i, line))
  end

  return string.format(
    [[
Buffer ID: %d
Name: %s
Path: %s
Filetype: %s
Content:
```%s
%s
```
]],
    buffer.id,
    buffer.name,
    buffer.path,
    buffer.filetype,
    buffer.filetype,
    table.concat(formatted, "\n")
  )
end

---Format a buffer's contents with line numbers included, for use in a markdown file
---@param bufnr number
---@param range? table
---@return string
function M.format_with_line_numbers(bufnr, range)
  return format(M.get_info(bufnr), M.get_content(bufnr, range))
end

---Format a buffer's contents for use in a markdown file
---@param bufnr number
---@param range? table
---@return string
function M.format(bufnr, range)
  local buffer = M.get_info(bufnr)

  return string.format(
    [[```%s
%s
```]],
    buffer.filetype,
    M.get_content(bufnr, range)
  )
end

---Check if a buffer is a codecompanion buffer
---@param bufnr integer? default to current buffer
---@return boolean?
function M.is_codecompanion_buffer(bufnr)
  return vim.b[bufnr or 0].codecompanion
end

---Set filetype and buffer-local variable to mark a buffer as a codecompanion
---buffer
---
---Notice that we first set the buffer-local variable and then the filetype so
---that user can set autocmds on `FileType` event and check if the buffer is a
---codecompanion buffer by checking `vim.b.codecompanion` variable
---@param bufnr integer? default to current buffer
function M.set_codecompanion_buffer(bufnr)
  vim.b[bufnr or 0].codecompanion = true
  vim.bo[bufnr or 0].filetype = "markdown"
end

return M
