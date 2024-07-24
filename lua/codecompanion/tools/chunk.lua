local TOOL_STATUS = require("codecompanion.tools.autocmd").TOOL_STATUS

---@class CodeCompanion.CopilotToolChunkResp
---@field bufnr number the buffer number
---@field status CodeCompanion.CopilotToolStatus status of the tool
---@field stream_output string when status is progress
---@field final_output string when status is success
---@field error string when status is error
local CopilotToolChunkResp = {}

---new start when you impl your own tool run method, you should send this chunk first
---@param bufnr number chat buffer number
function CopilotToolChunkResp.new_start(bufnr)
  local self = setmetatable({ bufnr = bufnr, status = TOOL_STATUS.start }, CopilotToolChunkResp)
  return self
end

--- new progress chunk which is used to show the stream output of a running tool
---@param bufnr number chat buffer number
---@param stream_output string
function CopilotToolChunkResp.new_progress(bufnr, stream_output)
  local self =
    setmetatable({ bufnr = bufnr, stream_output = stream_output, status = TOOL_STATUS.progress }, CopilotToolChunkResp)
  return self
end

--- new final chunk which is used to show the final output of a tool
---@param bufnr number chat buffer number
---@param final_output? string
function CopilotToolChunkResp.new_final(bufnr, final_output)
  local self =
    setmetatable({ bufnr = bufnr, final_output = final_output, status = TOOL_STATUS.final }, CopilotToolChunkResp)
  return self
end

--- new error chunk which is used to show the error output of a tool
---@param bufnr number chat buffer number
---@param error string
function CopilotToolChunkResp.new_error(bufnr, error)
  local self = setmetatable({ bufnr = bufnr, error = error, status = TOOL_STATUS.error }, CopilotToolChunkResp)
  return self
end

return CopilotToolChunkResp
