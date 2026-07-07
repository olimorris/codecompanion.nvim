local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "real_world_python.py.input"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Read a realistic Python config class",
  name = "Real-world Python config",
  tools = { "read_file", "insert_edit_into_file" },

  setup = function()
    local input_path = vim.fs.joinpath(FIXTURES, input_file)
    local test_file = vim.fn.tempname() .. ".py"
    files.write_to_path(test_file, files.read(input_path))
    return { input_path = input_path, test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[First use @{read_file} to read `%s`, then use @{insert_edit_into_file} to make these three changes in a single tool call:

1. In DEFAULTS, change `"pool_size": 5` to `"pool_size": 10`
2. In DEFAULTS, change `"ttl": 300` to `"ttl": 600`
3. In `_load_file`, add `!r` to the first error message: `f"config file not found: {path}"` → `f"config file not found: {path!r}"`

Read the file first to get the exact content. Do not ask for permission — call the tools directly.]],
      ctx.test_file
    )
  end,

  test = function(ctx, run)
    if vim.fn.executable("python3") == 0 then
      return false, "python3 not available"
    end
    local result = vim.system({ "python3", ctx.test_file }):wait()
    if result.code ~= 0 then
      return false, "execution failed: " .. vim.trim(result.stderr or "")
    end
    local output = vim.trim(result.stdout)
    if output ~= "600/10" then
      return false, "expected '600/10', got: " .. output
    end
    for _, call in ipairs(run.tool_calls) do
      if call.name == "read_file" then
        return true
      end
    end
    return false, "read_file was not called"
  end,
}
