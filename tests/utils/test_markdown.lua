local h = require("tests.helpers")
local markdown = require("codecompanion.utils.markdown")
local new_set = MiniTest.new_set

local T = new_set()

---Recover what a Markdown reader sees inside the first code block of `str`
---@param str string
---@return string|nil content
---@return number blocks
local function read_back(str)
  -- A closing run of backticks at end-of-string with no newline is not recognised as a closer
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

T["Markdown utils"]["form_codeblock"] = new_set()

T["Markdown utils"]["form_codeblock"]["wraps content without a filetype"] = function()
  h.eq("````\nhello\n````", markdown.form_codeblock("hello"))
end

T["Markdown utils"]["form_codeblock"]["renders the filetype on the opening line"] = function()
  h.eq("````lua\nlocal x = 1\n````", markdown.form_codeblock("local x = 1", { ft = "lua" }))
end

T["Markdown utils"]["form_codeblock"]["does not double the trailing newline"] = function()
  h.eq("````\nhello\n````", markdown.form_codeblock("hello\n"))
end

T["Markdown utils"]["form_codeblock"]["preserves an intentional trailing blank line"] = function()
  h.eq("````\nhello\n\n````", markdown.form_codeblock("hello\n\n"))
end

T["Markdown utils"]["form_codeblock"]["handles empty content"] = function()
  h.eq("````\n````", markdown.form_codeblock(""))
end

T["Markdown utils"]["form_codeblock"]["uses only the first line of the filetype"] = function()
  h.eq("````lua\nx\n````", markdown.form_codeblock("x", { ft = "lua\nnot a language" }))
end

T["Markdown utils"]["form_codeblock"]["stays parseable despite a hostile filetype"] = function()
  local _, blocks = read_back(markdown.form_codeblock("x", { ft = "lua\n````\nboom" }))
  h.eq(1, blocks)
end

T["Markdown utils"]["form_codeblock"]["DOES NOT grow the backticks for a three-backtick block"] = function()
  h.eq("````\na\n```\nb\n```\nc\n````", markdown.form_codeblock("a\n```\nb\n```\nc"))
end

T["Markdown utils"]["form_codeblock"]["grows the backticks for a colliding payload"] = function()
  h.eq("`````\na\n````\nb\n`````", markdown.form_codeblock("a\n````\nb"))
end

T["Markdown utils"]["form_codeblock round trip"] = new_set({
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

T["Markdown utils"]["form_codeblock round trip"]["recovers the payload from one block"] = function(payload)
  local content, blocks = read_back(markdown.form_codeblock(payload))
  local expected = payload:sub(-1) == "\n" and payload or payload .. "\n"
  h.eq(expected, content)
  h.eq(1, blocks)
end

return T
