-- Small 10-line file; single constant change.
-- Validates that the model sends a minimal edit, not a full-file rewrite.
-- old_string should be one or two lines, not the entire file.

local CONTENT = {
  "local M = {}",
  "",
  "local VERSION = '1.0.0'",
  "local MAX_CONNECTIONS = 10",
  "local RETRY_DELAY_MS = 500",
  "",
  "function M.version()",
  "  return VERSION",
  "end",
  "",
  "return M",
}

local EXPECTED = {
  "local M = {}",
  "",
  "local VERSION = '1.0.0'",
  "local MAX_CONNECTIONS = 25",
  "local RETRY_DELAY_MS = 500",
  "",
  "function M.version()",
  "  return VERSION",
  "end",
  "",
  "return M",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: one-line change in small file — old_string must be minimal, not a full-file rewrite",
  name = "Overwrite trap",
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

Change `MAX_CONNECTIONS` from `10` to `25`. Make a targeted edit — your old_string should contain only the line(s) needed to uniquely identify the change, not the entire file.

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      table.concat(CONTENT, "\n")
    )
  end,

  validate = function(ctx, run)
    local actual = vim.fn.readfile(ctx.test_file)
    if actual[#actual] == "" then
      actual[#actual] = nil
    end
    local file_ok = vim.deep_equal(actual, EXPECTED)

    -- old_string should be well under half the file length
    local file_len = #table.concat(CONTENT, "\n")
    local minimal = true
    for _, call in ipairs(run.tool_calls) do
      if call.name == "insert_edit_into_file" then
        local ok, args = pcall(vim.json.decode, call.arguments)
        if ok and args and args.edits then
          for _, edit in ipairs(args.edits) do
            if edit.old_string and #edit.old_string > file_len * 0.5 then
              minimal = false
            end
          end
        end
      end
    end

    return file_ok and minimal,
      {
        actual = table.concat(actual, "\n"),
        expected = table.concat(EXPECTED, "\n"),
        minimal_edit = minimal,
        file_len = file_len,
      }
  end,
}
