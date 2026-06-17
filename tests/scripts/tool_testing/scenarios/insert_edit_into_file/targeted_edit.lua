local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "targeted_edit.lua.input"
local expected_file = "targeted_edit.lua.expected"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Change one constant in a small file",
  name = "Targeted single-line edit",
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

Change `MAX_CONNECTIONS` from `10` to `25`. Make a targeted edit — your old_string should contain only the line(s) needed to uniquely identify the change, not the entire file.

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      files.read(ctx.input_path)
    )
  end,

  test = function(ctx, run)
    local actual = files.read(ctx.test_file)
    local expected = files.read(vim.fs.joinpath(FIXTURES, expected_file))
    if actual ~= expected then
      return false, "content mismatch"
    end

    -- old_string should be well under half the file length
    local file_len = #files.read(vim.fs.joinpath(FIXTURES, input_file))
    for _, call in ipairs(run.tool_calls) do
      if call.name == "insert_edit_into_file" then
        local ok, args = pcall(vim.json.decode, call.arguments)
        if ok and args and args.edits then
          for _, edit in ipairs(args.edits) do
            if edit.old_string and #edit.old_string > file_len * 0.5 then
              return false, "old_string was more than half the file"
            end
          end
        end
      end
    end

    return true
  end,
}
