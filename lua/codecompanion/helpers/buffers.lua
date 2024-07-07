local api = vim.api

---@param bufnr number
---@return string
local function get_content(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  return content
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
function M.get_opened_content(ft, bufs)
  local buffers = bufs or api.nvim_list_bufs()
  local content = {}

  for _, buf in ipairs(buffers) do
    if api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == ft then
      local filename = api.nvim_buf_get_name(buf)
      local name = filename:match("^.+/(.+)$")
      content[name] = get_content(buf)
    end
  end

  return content
end

---Formats the buffers into a markdown string
---@param buf_content table(<name><content>) The buffers to format
---@param ft string The filetype of the buffers
---@return string
function M.format(buf_content, ft)
  local formatted = {}

  for name, content in pairs(buf_content) do
    table.insert(formatted, name .. ":\n\n```" .. ft .. "\n" .. content .. "\n```")
  end

  return table.concat(formatted, "\n\n")
end

return M
