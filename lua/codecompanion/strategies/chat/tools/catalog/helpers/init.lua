local fmt = string.format

local M = {}

---Rejection message back to the LLM
---@param self CodeCompanion.Tools.Tool
---@param tools CodeCompanion.Tools
---@param cmd table
---@param opts table
---@return nil
M.rejected = function(self, tools, cmd, opts)
  opts = opts or {}

  local rejection = opts.message or "The user declined to execute the tool"
  if opts.reason then
    rejection = fmt('%s, with the reason: "%s"', rejection, opts.reason)
  end

  return tools.chat:add_tool_output(self, rejection)
end

return M
