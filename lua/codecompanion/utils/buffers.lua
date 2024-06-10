local api = vim.api

local M = {}

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

function M.format(buffers, ft)
  local formatted = {}

  for name, content in pairs(buffers) do
    table.insert(formatted, name .. ":\n\n```" .. ft .. "\n" .. content .. "\n```")
  end

  return table.concat(formatted, "\n\n")
end

return M
