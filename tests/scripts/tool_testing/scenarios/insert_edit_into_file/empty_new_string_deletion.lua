-- Deleting a function block entirely by setting new_string to "".
-- The model must include the blank line separators so the result is clean.

local CONTENT = {
  "local M = {}",
  "",
  "function M.validate(input)",
  "  if type(input) ~= 'string' then",
  "    return false, 'expected string'",
  "  end",
  "  if #input == 0 then",
  "    return false, 'cannot be empty'",
  "  end",
  "  return true, nil",
  "end",
  "",
  "function M.format(input)",
  "  return input:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')",
  "end",
  "",
  "-- Deprecated: use M.format instead",
  "function M.normalize(input)",
  "  return (input:gsub('%s+', ' '))",
  "end",
  "",
  "function M.transform(input)",
  "  local ok, err = M.validate(input)",
  "  if not ok then",
  "    return nil, err",
  "  end",
  "  return M.format(input), nil",
  "end",
  "",
  "return M",
}

local EXPECTED = {
  "local M = {}",
  "",
  "function M.validate(input)",
  "  if type(input) ~= 'string' then",
  "    return false, 'expected string'",
  "  end",
  "  if #input == 0 then",
  "    return false, 'cannot be empty'",
  "  end",
  "  return true, nil",
  "end",
  "",
  "function M.format(input)",
  "  return input:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')",
  "end",
  "",
  "function M.transform(input)",
  "  local ok, err = M.validate(input)",
  "  if not ok then",
  "    return nil, err",
  "  end",
  "  return M.format(input), nil",
  "end",
  "",
  "return M",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: delete a deprecated function by setting new_string to empty string",
  name = "Delete function with empty new_string",
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

Remove the deprecated `M.normalize` function entirely — including the comment above it and the blank line after `end`. Set new_string to an empty string `""` to delete it.

The result should have `M.format` followed directly by `M.transform` with a single blank line between them.

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
    local content = table.concat(actual, "\n")
    local still_has_normalize = content:find("M.normalize") ~= nil
    return ok and not still_has_normalize,
      {
        actual = content,
        expected = table.concat(EXPECTED, "\n"),
        still_has_normalize = still_has_normalize,
      }
  end,
}
