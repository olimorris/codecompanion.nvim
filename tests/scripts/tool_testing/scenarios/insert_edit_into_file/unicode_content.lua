local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "unicode_content.lua.input"
local expected_file = "unicode_content.lua.expected"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Edit a file containing an emoji",
  name = "Unicode content",
  tools = { "insert_edit_into_file" },

  setup = function()
    local input_path = vim.fs.joinpath(FIXTURES, input_file)
    local test_file = vim.fn.tempname() .. ".lua"
    files.write_to_path(test_file, files.read(input_path))
    return { input_path = input_path, test_file = test_file }
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
      files.read(ctx.input_path)
    )
  end,

  test = function(ctx)
    local actual = files.read(ctx.test_file)
    local expected = files.read(vim.fs.joinpath(FIXTURES, expected_file))
    return actual == expected, actual ~= expected and "content mismatch" or nil
  end,
}
