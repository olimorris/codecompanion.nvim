-- Inserting at the very top of a file.
-- The model must anchor on the first line of the file with no "above" context.

local CONTENT = {
  "local M = {}",
  "",
  "local function split(str, sep)",
  "  local parts = {}",
  "  local pattern = string.format('([^%s]*)', sep)",
  "  for part in str:gmatch(pattern) do",
  "    if part ~= '' then",
  "      table.insert(parts, part)",
  "    end",
  "  end",
  "  return parts",
  "end",
  "",
  "function M.parse_path(path)",
  "  return split(path, '/')",
  "end",
  "",
  "function M.join_path(parts)",
  "  return table.concat(parts, '/')",
  "end",
  "",
  "return M",
}

local EXPECTED = {
  "local log = require('codecompanion.utils.log')",
  "",
  "local M = {}",
  "",
  "local function split(str, sep)",
  "  local parts = {}",
  "  local pattern = string.format('([^%s]*)', sep)",
  "  for part in str:gmatch(pattern) do",
  "    if part ~= '' then",
  "      table.insert(parts, part)",
  "    end",
  "  end",
  "  return parts",
  "end",
  "",
  "function M.parse_path(path)",
  "  return split(path, '/')",
  "end",
  "",
  "function M.join_path(parts)",
  "  return table.concat(parts, '/')",
  "end",
  "",
  "return M",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: insert a require statement at the very top of the file",
  name = "Top-of-file insertion",
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

Add `local log = require('codecompanion.utils.log')` as the very first line of the file, followed by a blank line before `local M = {}`.

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
