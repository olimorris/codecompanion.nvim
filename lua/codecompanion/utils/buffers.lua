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
  return vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ":.")
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

---Format buffer content with XML wrapper for LLM consumption
---@param selected table Buffer info { bufnr: number, path: string, name?: string }
---@param opts? table Options { message?: string, range?: table }
---@return string content The XML-wrapped content
---@return string id The buffer reference ID
---@return string filename The buffer filename
function M.format_for_llm(selected, opts)
  opts = opts or {}
  local bufnr = selected.bufnr
  local path = selected.path

  -- Handle unloaded buffers
  local content
  if not api.nvim_buf_is_loaded(bufnr) then
    local file_content = require("plenary.path").new(path):read()
    if file_content == "" then
      error("Could not read the file: " .. path)
    end
    content = string.format(
      [[```%s
%s
```]],
      vim.filetype.match({ filename = path }),
      M.add_line_numbers(vim.trim(file_content))
    )
  else
    content = string.format(
      [[```%s
%s
```]],
      M.get_info(bufnr).filetype,
      M.add_line_numbers(M.get_content(bufnr, opts.range))
    )
  end

  local filename = vim.fn.fnamemodify(path, ":t")
  local relative_path = vim.fn.fnamemodify(path, ":.")

  -- Generate consistent ID
  local id = "<buf>" .. relative_path .. "</buf>"

  local message = opts.message or "File content"

  local formatted_content = string.format(
    [[<attachment filepath="%s" buffer_number="%s">%s:
%s</attachment>]],
    relative_path,
    bufnr,
    message,
    content
  )

  return formatted_content, id, filename
end

---Format viewport content with XML wrapper for LLM consumption
---@param buf_lines table Buffer lines from get_visible_lines()
---@return string content The XML-wrapped content for all visible buffers
function M.format_viewport_for_llm(buf_lines)
  local formatted = {}

  for bufnr, ranges in pairs(buf_lines) do
    local info = M.get_info(bufnr)
    local relative_path = vim.fn.fnamemodify(info.path, ":.")

    for _, range in ipairs(ranges) do
      local start_line, end_line = range[1], range[2]

      local buffer_content = M.get_content(bufnr, { start_line - 1, end_line })
      local content = string.format(
        [[```%s
%s
```]],
        info.filetype,
        buffer_content
      )

      local excerpt_info = string.format("Excerpt from %s, lines %d to %d", relative_path, start_line, end_line)

      local formatted_content = string.format(
        [[<attachment filepath="%s" buffer_number="%s">%s:
%s</attachment>]],
        relative_path,
        bufnr,
        excerpt_info,
        content
      )

      table.insert(formatted, formatted_content)
    end
  end

  return table.concat(formatted, "\n\n")
end

---Check if a filepath is open as a buffer and return the buffer number
---@param filepath string The filepath to check
---@return number|nil Buffer number if found, nil otherwise
function M.get_bufnr_from_filepath(filepath)
  local normalized_path = vim.fn.fnamemodify(filepath, ":p")

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

return M
