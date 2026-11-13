local fmt = string.format

local M = {}

---@generic T
---@param value T
---@return T|nil
M.null_to_nil = function(value)
  if value == vim.NIL then
    return nil
  end
  return value
end

---Rejection message back to the LLM
---@param self CodeCompanion.Tools.Tool
---@param opts table
---@return nil
M.rejected = function(self, opts)
  opts = opts or {}

  local rejection = opts.message or "The user declined to execute the tool"
  if opts.opts and opts.opts.reason then
    rejection = fmt('%s, with the reason: "%s"', rejection, opts.opts.reason)
  end

  return opts.tools.chat:add_tool_output(self, { content = rejection })
end

return M
