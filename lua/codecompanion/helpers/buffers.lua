local api = vim.api

---@param bufnr number
---@return string
local function get_content(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  return content
end

---@param bufnr number
---@return table
local function get_buffer_info(bufnr)
  return {
    id = bufnr,
    name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t"),
    path = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.api.nvim_buf_get_option(bufnr, "filetype"),
  }
end

local function format_buffer_content(buffer_info, content)
  local lines = vim.split(content, "\n")
  local formatted_content = {}
  for i, line in ipairs(lines) do
    table.insert(formatted_content, string.format("%d  %s", i, line))
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
    buffer_info.id,
    buffer_info.name,
    buffer_info.path,
    buffer_info.filetype,
    buffer_info.filetype,
    table.concat(formatted_content, "\n")
  )
end

local M = {}

---@param bufnr number
---@return table
function M.get_buffer_content(bufnr)
  local content = {}

  local name = api.nvim_buf_get_name(bufnr)
  content[name] = get_content(bufnr)

  return content
end

---Fetches all of the open buffers with the specified filetype
---@param ft string The filetype to filter the buffers by
---@param bufs? table The table of buffers to filter
---@return table
function M.get_open_buffers(ft, bufs)
  local buffers = bufs or api.nvim_list_bufs()
  local content = {}

  for _, buf in ipairs(buffers) do
    if api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == ft then
      local filename = api.nvim_buf_get_name(buf)
      content[filename] = get_content(buf)
    end
  end

  return content
end

function M.get_qf_buffers()
  local qf_list = vim.fn.getqflist()

  for _, item in ipairs(qf_list) do
    local bufnr = item.bufnr
    local filename = item.text
    item.content = get_content(bufnr)
  end
end

---Formats the buffers into a markdown string
---@param buf_content table(<name><content>) The buffers to format
---@param ft string The filetype of the buffers
---@return string
function M.format(buf_content, ft)
  local formatted = {}

  for name, content in pairs(buf_content) do
    local bufnr = vim.fn.bufnr(name)
    local buffer_info = get_buffer_info(bufnr)
    table.insert(formatted, format_buffer_content(buffer_info, content))
  end

  return table.concat(formatted, "\n\n")
end

return M
