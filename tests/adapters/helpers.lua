local M = {}

function M.chat_buffer_output(response, adapter)
  local output = { output = { content = "", role = "assistant" } }

  for _, data in ipairs(response) do
    local chunk = adapter.handlers.chat_output(adapter, data.request)
    if chunk and chunk.output then
      if chunk.output.role then
        output.output.role = chunk.output.role
      end
      if chunk.output.content then
        output.output.content = output.output.content .. chunk.output.content
      end
    end
  end

  return output.output
end

function M.inline_buffer_output(response, adapter)
  return adapter.handlers.inline_output(adapter, response[1].request.body).output
end

return M
