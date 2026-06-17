local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "tab_indented_python.py.input"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Edit tab-indented Python",
  name = "Tab-indented Python",
  tools = { "insert_edit_into_file" },

  setup = function()
    local input_path = vim.fs.joinpath(FIXTURES, input_file)
    local test_file = vim.fn.tempname() .. ".py"
    files.write_to_path(test_file, files.read(input_path))
    return { input_path = input_path, test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[Use @{insert_edit_into_file} to edit the file at `%s`.

Current content (indented with real tab characters, not spaces):
```python
%s
```

Change `_transform` so it multiplies `item['value']` by `self.config.multiplier` instead of `2`.

Important: the file uses real tab characters for indentation. Your old_string and new_string must use real tabs, not spaces.

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      files.read(ctx.input_path)
    )
  end,

  test = function(ctx)
    if vim.fn.executable("python3") == 0 then
      return false, "python3 not available"
    end
    local result = vim.system({ "python3", ctx.test_file }):wait()
    if result.code ~= 0 then
      return false, "execution failed: " .. vim.trim(result.stderr or "")
    end
    local output = vim.trim(result.stdout)
    return output == "12", output ~= "12" and "expected '12', got: " .. output or nil
  end,
}
