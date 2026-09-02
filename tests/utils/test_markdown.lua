local h = require("tests.helpers")
local markdown = require("codecompanion.utils.markdown")
local new_set = MiniTest.new_set

local T = new_set()

---Recover what a Markdown reader sees inside the first code block of `str`
---@param str string
---@return string|nil content
---@return number blocks How many code blocks the string parses as
local function read_back(str)
  -- The trailing newline mimics a buffer, which always holds whole lines: a
  -- closing fence at end-of-string with no newline is not recognised as a closer.
  local source = str .. "\n"
  local tree = vim.treesitter.get_string_parser(source, "markdown"):parse()[1]
  local content
  local query = vim.treesitter.query.parse("markdown", "(code_fence_content) @content")
  for _, node in query:iter_captures(tree:root(), source) do
    content = content or vim.treesitter.get_node_text(node, source)
  end
  local blocks = 0
  query = vim.treesitter.query.parse("markdown", "(fenced_code_block) @block")
  for _ in query:iter_captures(tree:root(), source) do
    blocks = blocks + 1
  end
  return content, blocks
end

T["Markdown utils"] = new_set()

T["Markdown utils"]["fence"] = new_set()

T["Markdown utils"]["fence"]["defaults to four backticks"] = function()
  h.eq("````", markdown.fence("plain text"))
end

T["Markdown utils"]["fence"]["honours a lower minimum"] = function()
  h.eq("```", markdown.fence("plain text", 3))
end

T["Markdown utils"]["fence"]["honours a higher minimum"] = function()
  h.eq("`````", markdown.fence("plain text", 5))
end

T["Markdown utils"]["fence"]["is not inflated by inline backticks"] = function()
  -- A single backtick cannot close a four-backtick fence.
  h.eq("````", markdown.fence("use `x` and ``y`` here"))
end

T["Markdown utils"]["fence"]["is not inflated by a three-backtick block"] = function()
  h.eq("````", markdown.fence("a\n```\nb\n```\nc"))
end

T["Markdown utils"]["fence"]["grows past a four-backtick run"] = function()
  h.eq("`````", markdown.fence("a\n````\nb"))
end

T["Markdown utils"]["fence"]["grows past a six-backtick run"] = function()
  h.eq("```````", markdown.fence("a\n``````\nb"))
end

T["Markdown utils"]["fence"]["grows past a run even when a minimum is given"] = function()
  h.eq("`````", markdown.fence("a\n````\nb", 3))
end

T["Markdown utils"]["fence"]["tolerates nil"] = function()
  h.eq("````", markdown.fence(nil))
end

T["Markdown utils"]["code_block"] = new_set()

T["Markdown utils"]["code_block"]["wraps content without an info string"] = function()
  h.eq("````\nhello\n````", markdown.code_block("hello"))
end

T["Markdown utils"]["code_block"]["renders the info string on the opening fence"] = function()
  h.eq("````lua\nlocal x = 1\n````", markdown.code_block("local x = 1", { info = "lua" }))
end

T["Markdown utils"]["code_block"]["does not double the trailing newline"] = function()
  h.eq("````\nhello\n````", markdown.code_block("hello\n"))
end

T["Markdown utils"]["code_block"]["preserves an intentional trailing blank line"] = function()
  h.eq("````\nhello\n\n````", markdown.code_block("hello\n\n"))
end

T["Markdown utils"]["code_block"]["handles empty content"] = function()
  h.eq("````\n````", markdown.code_block(""))
end

T["Markdown utils"]["code_block"]["uses only the first line of the info string"] = function()
  -- A newline in the info string would end the opening fence's line early.
  h.eq("````lua\nx\n````", markdown.code_block("x", { info = "lua\nnot a fence" }))
end

T["Markdown utils"]["code_block"]["stays parseable despite a hostile info string"] = function()
  local _, blocks = read_back(markdown.code_block("x", { info = "lua\n````\nboom" }))
  h.eq(1, blocks)
end

T["Markdown utils"]["code_block"]["honours the minimum fence length"] = function()
  h.eq("```txt\nboom\n```", markdown.code_block("boom", { info = "txt", min = 3 }))
end

T["Markdown utils"]["code_block"]["grows the fence for a colliding payload"] = function()
  h.eq("`````\na\n````\nb\n`````", markdown.code_block("a\n````\nb"))
end

-- The property that actually matters: whatever the payload, a reader recovers it
-- verbatim from exactly one code block.
T["Markdown utils"]["code_block round trip"] = new_set({
  parametrize = {
    { "plain text" },
    { "a\n```\nb\n```\nc" },
    { "a\n````\nb" },
    { "a\n   ````\nb" },
    { "a\n    ````\nb" },
    { "a\n`````\nb" },
    { "# Title\n\n````lua\nlocal x = 1\n````\n\nProse." },
    { "unbalanced\n````\ntail" },
  },
})

T["Markdown utils"]["code_block round trip"]["recovers the payload from one block"] = function(payload)
  local content, blocks = read_back(markdown.code_block(payload))
  local expected = payload:sub(-1) == "\n" and payload or payload .. "\n"
  h.eq(expected, content)
  h.eq(1, blocks)
end

return T
