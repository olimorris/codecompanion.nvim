local api = vim.api

local M = {}

---Fetches all of the open buffers with the specified filetype
---@param ft string The filetype to filter the buffers by
---@return table
function M.get_open_buffers(ft)
  local buffers = api.nvim_list_bufs()
  local buffer_content = {}

  for _, buf in ipairs(buffers) do
    if api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == ft then
      local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
      local filename = api.nvim_buf_get_name(buf)
      local name = filename:match("^.+/(.+)$")
      buffer_content[name] = table.concat(lines, "\n")
    end
  end

  return buffer_content
end

---Formats the buffers into a markdown string
---@param buffers table The buffers to format
---@param ft string The filetype of the buffers
---@return string
function M.format(buffers, ft)
  local formatted = {}

  for name, content in pairs(buffers) do
    table.insert(formatted, name .. ":\n\n```" .. ft .. "\n" .. content .. "\n```")
  end

  return table.concat(formatted, "\n\n")
end

return M
