local CONTENT = {
  "local M = {}",
  "",
  "function M.greet(name)",
  '  return "Hello, " .. name',
  "end",
  "",
  "return M",
}

local EXPECTED = {
  "local M = {}",
  "",
  "function M.welcome(name)",
  '  return "Welcome, " .. name',
  "end",
  "",
  "return M",
}

return {
  description = "insert_edit_into_file: rename a function and a string literal",
  name = "Simple file edit",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    local content = table.concat(CONTENT, "\n")
    return string.format(
      [[Use @{insert_edit_into_file} to edit the file at `%s`.

Current content:
```lua
%s
```

Changes needed:
1. Change the function name from `greet` to `welcome`
2. Change "Hello" to "Welcome"

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      content
    )
  end,

  validate = function(ctx, _run)
    local actual = vim.fn.readfile(ctx.test_file)
    if actual[#actual] == "" then
      actual[#actual] = nil
    end
    local ok = vim.deep_equal(actual, EXPECTED)
    return ok, {
      actual = table.concat(actual, "\n"),
      expected = table.concat(EXPECTED, "\n"),
    }
  end,

  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,
}
