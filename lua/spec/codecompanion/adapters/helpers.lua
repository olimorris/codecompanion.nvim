local M = {}

function M.chat_buffer_output(stream_response, adapter)
  local output = {}

  for _, data in ipairs(stream_response) do
    output = adapter.args.handlers.chat_output(data.request)
  end

  return output.output
end

return M
