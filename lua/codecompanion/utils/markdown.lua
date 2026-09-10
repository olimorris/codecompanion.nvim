local M = {}

local MIN_BACKTICKS = 4

---Intelligently form backticks based on the content
---@param content string
---@return string
local function form_backticks(content)
  local longest = 0
  for run in content:gmatch("`+") do
    longest = math.max(longest, #run)
  end

  return ("`"):rep(math.max(MIN_BACKTICKS, longest + 1))
end

---@param content string
---@param opts? { ft?: string }
---@return string
function M.form_codeblock(content, opts)
  opts = opts or {}

  -- A newline in the filetype would end the opening line early, breaking the block
  local ft = (opts.ft or ""):match("^[^\r\n]*")

  local backticks = form_backticks(content)
  local opening = backticks .. ft

  if content == "" then
    return opening .. "\n" .. backticks
  end

  local separator = content:sub(-1) == "\n" and "" or "\n"
  return opening .. "\n" .. content .. separator .. backticks
end

return M
