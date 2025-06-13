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
    content = "```"
      .. vim.filetype.match({ filename = path })
      .. "\n"
      .. M.add_line_numbers(vim.trim(file_content))
      .. "\n```"
  else
    content = M.format_with_line_numbers(bufnr, opts.range)
  end

  local filename = vim.fn.fnamemodify(path, ":t")
  local relative_path = vim.fn.fnamemodify(path, ":.")

  -- Generate consistent ID
  local id = "<buf>" .. relative_path .. "</buf>"

  local message = opts.message or "Buffer content"

  local formatted_content = string.format(
    [[<buffer filepath="%s" number="%s">%s. From %s:
%s</buffer>]],
    relative_path,
    bufnr,
    message,
    relative_path,
    content
  )

  return formatted_content, id, filename
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
    [[```%s
%s
```]],
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

return M
