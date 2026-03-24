local fmt = string.format

local M = {}

---Rejection message back to the LLM
---@param self CodeCompanion.Tools.Tool
---@param meta table
---@return nil
M.rejected = function(self, meta)
  meta = meta or {}

  local rejection = meta.message or "The user declined to execute the tool"
  if meta.opts and meta.opts.reason then
    rejection = fmt('%s, with the reason: "%s"', rejection, meta.opts.reason)
  end

  return meta.tools.chat:add_tool_output(self, rejection)
end

return M
