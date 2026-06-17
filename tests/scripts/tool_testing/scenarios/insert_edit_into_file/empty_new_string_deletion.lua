local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "empty_new_string_deletion.lua.input"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Delete a deprecated function block by setting new_string to empty string",
  name = "Delete function with empty new_string",
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

Remove the deprecated `M.normalize` function entirely — including the comment above it and the blank line after `end`. Set new_string to an empty string `""` to delete it.

The result should have `M.format` followed directly by `M.transform` with a single blank line between them.

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      files.read(ctx.input_path)
    )
  end,

  test = function(ctx)
    if vim.fn.executable("nvim") == 0 then
      return false, "nvim not available"
    end
    local result = vim.system({ "nvim", "-l", ctx.test_file }):wait()
    if result.code ~= 0 then
      return false, "execution failed: " .. vim.trim(result.stderr or "")
    end
    local output = vim.trim(result.stderr)
    return output == "deleted", output ~= "deleted" and "expected 'deleted', got: " .. output or nil
  end,
}
