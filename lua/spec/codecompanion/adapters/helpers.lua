local M = {}

function M.chat_buffer_output(stream_response, adapter, messages)
  local output = {}

  for _, data in ipairs(stream_response) do
    data = adapter.callbacks.format_data(data.request)
    data = vim.json.decode(data, { luanil = { object = true } })

    output = adapter.callbacks.output_chat(data, messages, output)
  end

  return output
end

return M
