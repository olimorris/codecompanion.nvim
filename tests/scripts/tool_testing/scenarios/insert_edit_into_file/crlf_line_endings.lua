local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "crlf_line_endings.lua.input"
local expected_file = "crlf_line_endings.lua.expected"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Edit a file with Windows CRLF line endings",
  name = "CRLF line endings",
  tools = { "insert_edit_into_file" },

  setup = function()
    local input_path = vim.fs.joinpath(FIXTURES, input_file)
    local test_file = vim.fn.tempname() .. ".lua"
    local f = assert(io.open(test_file, "wb"))
    f:write(files.read(input_path))
    f:close()
    return { input_path = input_path, test_file = test_file }
  end,

  prompt = function(ctx)
    local display = files.read(ctx.input_path):gsub("\r\n", "\n")
    return string.format(
      [[Use @{insert_edit_into_file} to edit the file at `%s`.

Current content:
```lua
%s
```

Change `'Hello, '` to `'Hi, '` in the `greet` function.

Note: the file uses Windows-style CRLF line endings. Your old_string should match the content as-is.

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      display
    )
  end,

  test = function(ctx)
    local f = assert(io.open(ctx.test_file, "rb"))
    local actual_raw = f:read("*a")
    f:close()
    local expected = files.read(vim.fs.joinpath(FIXTURES, expected_file))
    local content_ok = actual_raw == expected
    local has_crlf = actual_raw:find("\r\n") ~= nil
    local no_bare_lf = not actual_raw:find("[^\r]\n")
    if not content_ok then
      return false, "content mismatch"
    end
    if not has_crlf then
      return false, "CRLF line endings lost"
    end
    if not no_bare_lf then
      return false, "bare LF introduced"
    end
    return true
  end,
}
