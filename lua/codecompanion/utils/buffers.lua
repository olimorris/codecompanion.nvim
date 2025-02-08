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

---Get the formatted name of a buffer from its number
---@param bufnr number
---@return table
function M.name_from_bufnr(bufnr)
  return vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ":t")
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
Buffer Number: %d
Name: %s
Path: %s
Filetype: %s
Content:
```%s
%s
```
]],
    buffer.number,
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

return M
