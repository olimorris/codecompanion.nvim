-- Inserting a new function before `return M` at the end of a file.
-- The model must anchor on `return M` as the lower bound.

local CONTENT = {
  "local M = {}",
  "",
  "function M.encode(data)",
  "  return vim.json.encode(data)",
  "end",
  "",
  "function M.decode(str)",
  "  local ok, result = pcall(vim.json.decode, str)",
  "  if not ok then",
  "    return nil, 'invalid JSON'",
  "  end",
  "  return result, nil",
  "end",
  "",
  "return M",
}

local EXPECTED = {
  "local M = {}",
  "",
  "function M.encode(data)",
  "  return vim.json.encode(data)",
  "end",
  "",
  "function M.decode(str)",
  "  local ok, result = pcall(vim.json.decode, str)",
  "  if not ok then",
  "    return nil, 'invalid JSON'",
  "  end",
  "  return result, nil",
  "end",
  "",
  "function M.pretty(data)",
  "  local str = M.encode(data)",
  "  return str and str:gsub(',', ',\\n') or nil",
  "end",
  "",
  "return M",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: append a new function before `return M` at end of file",
  name = "End-of-file insertion",
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

Add a new function `M.pretty(data)` before `return M`. The function should call `M.encode(data)` and return the result with commas followed by newlines, or nil if encoding fails:

```lua
function M.pretty(data)
  local str = M.encode(data)
  return str and str:gsub(',', ',\n') or nil
end
```

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
