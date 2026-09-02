--[[
Helpers for embedding arbitrary text in Markdown.

The invariant this module exists to guarantee: a fence returned by `fence()` is
always longer than the longest run of backticks in the content it will wrap, so
the content cannot terminate it. This is the rule CommonMark and GitHub use for
nesting, and the one Tree-sitter implements, which matters because the chat
buffer is parsed as Markdown.

The content is never rewritten. There is no escape mechanism inside a fenced
code block, so altering the payload's own backticks would mean changing bytes the
user reads and copies, and it is not even well defined for a payload whose fences
are already unbalanced (a truncated file read, a diff hunk that starts inside a
code block). A longer outer fence is robust to all of those.
--]]

local CONSTANTS = {
  MIN_FENCE = 4,
}

local M = {}

---A fence long enough that `content` cannot terminate it
---@param content string The text that will be wrapped
---@param min? integer Minimum fence length; defaults to 4
---@return string
function M.fence(content, min)
  local longest = 0
  for run in tostring(content or ""):gmatch("`+") do
    longest = math.max(longest, #run)
  end
  return ("`"):rep(math.max(min or CONSTANTS.MIN_FENCE, longest + 1))
end

---Wrap `content` in a fenced code block it cannot terminate
---
---The closing fence always starts its own line: exactly one newline separates it
---from the content, whether or not the content already ends in one. Trailing
---blank lines within the content are preserved.
---@param content string The text to wrap
---@param opts? { info?: string, min?: integer } `info` is the info string (a filetype, "diff", ...); only its first line is used, since it shares the opening fence's line
---@return string
function M.code_block(content, opts)
  opts = opts or {}
  content = content == nil and "" or tostring(content)

  -- The info string shares the opening fence's line, so only its first line can
  -- be used: a newline in it would end that line early and break the block.
  local info = tostring(opts.info or ""):match("^[^\r\n]*")

  local fence = M.fence(content, opts.min)
  local opening = fence .. info

  if content == "" then
    return opening .. "\n" .. fence
  end

  local separator = content:sub(-1) == "\n" and "" or "\n"
  return opening .. "\n" .. content .. separator .. fence
end

return M
