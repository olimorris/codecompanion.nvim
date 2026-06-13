-- File contains multi-byte Unicode characters (emoji).
-- The model must emit the emoji codepoints exactly in old_string.

local CONTENT = {
  "local M = {}",
  "",
  "M.messages = {",
  "  error = 'Something went wrong \xF0\x9F\x98\x9E',",
  "  processing = 'Processing your request... \xE2\x8F\xB3',",
  "  success = 'Done! \xE2\x9C\x85',",
  "  warning = 'Proceed with caution \xE2\x9A\xA0\xEF\xB8\x8F',",
  "  welcome = 'Welcome to CodeCompanion! \xF0\x9F\x8E\x89',",
  "}",
  "",
  "return M",
}

local EXPECTED = {
  "local M = {}",
  "",
  "M.messages = {",
  "  error = 'An error occurred \xF0\x9F\x98\x9E',",
  "  processing = 'Processing your request... \xE2\x8F\xB3',",
  "  success = 'Done! \xE2\x9C\x85',",
  "  warning = 'Proceed with caution \xE2\x9A\xA0\xEF\xB8\x8F',",
  "  welcome = 'Welcome to CodeCompanion! \xF0\x9F\x8E\x89',",
  "}",
  "",
  "return M",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: file contains emoji — model must emit multi-byte codepoints exactly in old_string",
  name = "Unicode content",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".lua"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[Use @{insert_edit_into_file} to edit the file at `%s`.

Current content:
```lua
%s
```

Change the `error` message from `'Something went wrong 😞'` to `'An error occurred 😞'`. Keep the emoji — only the text changes.

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      table.concat(CONTENT, "\n")
    )
  end,

  validate = function(ctx, _run)
    local actual = vim.fn.readfile(ctx.test_file)
    if actual[#actual] == "" then
      actual[#actual] = nil
    end
    local ok = vim.deep_equal(actual, EXPECTED)
    return ok, { actual = table.concat(actual, "\n"), expected = table.concat(EXPECTED, "\n") }
  end,
}
