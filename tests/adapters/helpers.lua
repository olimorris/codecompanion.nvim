local M = {}

function M.chat_buffer_output(response, adapter)
  local output = {}

  for _, data in ipairs(response) do
    output = adapter.handlers.chat_output(adapter, data.request)
  end

  return output.output
end

return M
