local assert = require("luassert")

local function parse(str)
  local parser = vim.treesitter.get_string_parser(str, "markdown")
  local query = vim.treesitter.query.parse(
    "markdown",
    [[
(section
  (atx_heading
    (atx_h2_marker))
  ((_) @content)+) @response
]]
  )
  local root = parser:parse()[1]:root()

  local last_section = nil
  local contents = {}

  for id, node in query:iter_captures(root, str) do
    if query.captures[id] == "response" then
      last_section = node
      contents = {}
    elseif query.captures[id] == "content" and last_section then
      table.insert(contents, vim.treesitter.get_node_text(node, str))
    end
  end

  if #contents > 0 then
    return { content = vim.trim(table.concat(contents, "\n")) }
  end

  return {}
end

local markdown = [[
## olimorris

Are you functioning?

##   CodeCompanion

Yes. What can I do for you?

## olimorris

Can you tell me why Ruby is so popular?

##   CodeCompanion

Certainly! Here's a summary of why Ruby is popular in 5 bullet points:

1. Elegant and readable syntax: Ruby's clean, expressive code is often described as close to natural language.
2. Rails framework: Ruby on Rails revolutionized web development, making Ruby a go-to language for building web applications quickly.
3. Strong community: Ruby has a passionate and supportive community that contributes to its ecosystem.
4. Productivity-focused: Ruby's design philosophy prioritizes developer happiness and rapid development.
5. Flexibility: It supports multiple programming paradigms, including object-oriented, functional, and procedural programming.]]

describe("Tree-sitter", function()
  it("can get the last message from a markdown buffer", function()
    local result = parse(markdown)

    assert.are.same({
      content = [[Certainly! Here's a summary of why Ruby is popular in 5 bullet points:

1. Elegant and readable syntax: Ruby's clean, expressive code is often described as close to natural language.
2. Rails framework: Ruby on Rails revolutionized web development, making Ruby a go-to language for building web applications quickly.
3. Strong community: Ruby has a passionate and supportive community that contributes to its ecosystem.
4. Productivity-focused: Ruby's design philosophy prioritizes developer happiness and rapid development.
5. Flexibility: It supports multiple programming paradigms, including object-oriented, functional, and procedural programming.]],
    }, result)
  end)

  it("can clear any block quotes from a message", function()
    local message = [[> Used 2 references:
> - config.lua
> - init.lua

What can you do?]]

    local parser = vim.treesitter.get_string_parser(message, "markdown")
    local query = vim.treesitter.query.get("markdown", "chat")
    local root = parser:parse()[1]:root()

    local refs = nil
    for id, node in query:iter_captures(root, message) do
      if query.captures[id] == "refs" then
        refs = node
      end
    end

    if refs then
      local start_row, _, end_row, _ = refs:range()
      message = vim.split(message, "\n")
      for i = start_row, end_row do
        message[i] = ""
      end
    end

    assert.are.same("What can you do?", vim.trim(table.concat(message, "\n")))
  end)
end)
