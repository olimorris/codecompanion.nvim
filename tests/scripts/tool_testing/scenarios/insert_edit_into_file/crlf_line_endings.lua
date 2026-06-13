-- File uses Windows CRLF (\r\n) line endings.
-- After editing, line endings must still be CRLF throughout.

-- CONTENT and EXPECTED are the raw file bytes (strings, not line arrays).
local CONTENT_RAW =
  "local M = {}\r\n\r\nM.VERSION = '1.0.0'\r\nM.NAME = 'myapp'\r\n\r\nfunction M.greet(name)\r\n  return 'Hello, ' .. name\r\nend\r\n\r\nreturn M\r\n"
local EXPECTED_RAW =
  "local M = {}\r\n\r\nM.VERSION = '1.0.0'\r\nM.NAME = 'myapp'\r\n\r\nfunction M.greet(name)\r\n  return 'Hi, ' .. name\r\nend\r\n\r\nreturn M\r\n"

-- Content shown to the model in the prompt (LF version for readability)
local CONTENT_DISPLAY = {
  "local M = {}",
  "",
  "M.VERSION = '1.0.0'",
  "M.NAME = 'myapp'",
  "",
  "function M.greet(name)",
  "  return 'Hello, ' .. name",
  "end",
  "",
  "return M",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: CRLF file — line endings must be preserved after edit",
  name = "CRLF line endings",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".lua"
    local f = assert(io.open(test_file, "wb"))
    f:write(CONTENT_RAW)
    f:close()
    return { test_file = test_file }
  end,

  prompt = function(ctx)
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
      table.concat(CONTENT_DISPLAY, "\n")
    )
  end,

  validate = function(ctx, _run)
    local f = assert(io.open(ctx.test_file, "rb"))
    local actual_raw = f:read("*a")
    f:close()
    local content_ok = actual_raw == EXPECTED_RAW
    local has_crlf = actual_raw:find("\r\n") ~= nil
    local no_bare_lf = not actual_raw:find("[^\r]\n")
    return content_ok and has_crlf and no_bare_lf,
      {
        actual = actual_raw:gsub("\r\n", "\n"),
        content_match = content_ok,
        expected = EXPECTED_RAW:gsub("\r\n", "\n"),
        has_crlf = has_crlf,
        no_bare_lf = no_bare_lf,
      }
  end,
}
