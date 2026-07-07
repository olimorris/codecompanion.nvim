local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "top_of_file_insertion.lua.input"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Insert a require statement at the very top of the file with no preceding context to anchor on",
  name = "Top-of-file insertion",
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

Add `local log = require('codecompanion.utils.log')` as the very first line of the file, followed by a blank line before `local M = {}`.

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      files.read(ctx.input_path)
    )
  end,

  test = function(ctx)
    if vim.fn.executable("luac") == 0 then
      return false, "luac not available"
    end
    local result = vim.system({ "luac", "-p", ctx.test_file }):wait()
    return result.code == 0, result.code ~= 0 and vim.trim(result.stderr or "") or nil
  end,
}
