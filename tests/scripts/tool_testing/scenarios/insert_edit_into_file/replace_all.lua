local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "replace_all.lua.input"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Rename an identifier that appears 12 times throughout a file",
  name = "Replace all occurrences",
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

Rename every occurrence of `user_id` to `account_id` throughout the entire file. The identifier appears 12 times — use `replace_all = true` so all occurrences are replaced in a single edit.

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      files.read(ctx.input_path)
    )
  end,

  test = function(ctx)
    local actual = files.read(ctx.test_file)
    local old_count = select(2, actual:gsub("user_id", ""))
    local new_count = select(2, actual:gsub("account_id", ""))
    if old_count > 0 then
      return false, old_count .. " occurrences of user_id remain"
    end
    if new_count < 10 then
      return false, "only " .. new_count .. " occurrences of account_id found"
    end
    return true
  end,
}
