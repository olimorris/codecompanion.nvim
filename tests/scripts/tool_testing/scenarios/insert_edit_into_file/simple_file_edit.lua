local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "simple_file_edit.lua.input"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Rename a function, update its string literal, and update the call site",
  name = "Simple file edit",
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

Changes needed:
1. Change the function name from `greet` to `welcome`
2. Change `"Hello, "` to `"Welcome, "`
3. Update the call site: `M.greet("World")` → `M.welcome("World")`

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      files.read(ctx.input_path)
    )
  end,

  test = function(ctx)
    if vim.fn.executable("nvim") == 0 then
      return false, "nvim not available"
    end
    local result = vim.system({ "nvim", "-l", ctx.test_file }):wait()
    if result.code ~= 0 then
      return false, "execution failed: " .. vim.trim(result.stderr or "")
    end
    local output = vim.trim(result.stderr)
    return output == "Welcome, World",
      output ~= "Welcome, World" and "expected 'Welcome, World', got: " .. output or nil
  end,
}
