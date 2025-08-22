local M = {}

---Determine if the tool call contains a diff object
---@param tool_call table
---@return boolean
function M.tool_has_diff(tool_call)
  if
    tool_call.content
    and tool_call.content[1]
    and tool_call.content[1].type
    and tool_call.content[1].type == "diff"
  then
    return true
  end
  return false
end

---Get the diff object from the tool call
---@param tool_call table
---@return table
function M.get_diff(tool_call)
  return {
    kind = tool_call.kind,
    new = tool_call.content[1].newText,
    old = tool_call.content[1].oldText,
    path = vim.fs.joinpath(vim.fn.getcwd(), tool_call.content[1].path),
    status = tool_call.status,
    title = tool_call.title,
    tool_call_id = tool_call.toolCallId,
  }
end

---Display the diff to the user along with their options to respond
function M.show_diff(request) end

return M
