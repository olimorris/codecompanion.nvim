local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "real_world_ruby.rb.input"
local expected_file = "real_world_ruby.rb.expected"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Read a realistic Ruby API client, then make two edits in one call",
  name = "Real-world Ruby client",
  tools = { "read_file", "insert_edit_into_file" },

  setup = function()
    local input_path = vim.fs.joinpath(FIXTURES, input_file)
    local test_file = vim.fn.tempname() .. ".rb"
    files.write_to_path(test_file, files.read(input_path))
    return { input_path = input_path, test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[First use @{read_file} to read `%s`, then use @{insert_edit_into_file} to make two changes in a single tool call:

1. Change `DEFAULT_TIMEOUT` from `5` to `30`
2. Add a `patch` method between `post` and `delete`:
```ruby
  def patch(path, body = {})
    request(:patch, path, body: body)
  end
```

Read the file first. Do not ask for permission — call the tools directly.]],
      ctx.test_file
    )
  end,

  test = function(ctx, run)
    if vim.fn.executable("ruby") == 0 then
      return false, "ruby not available"
    end
    local result = vim.system({ "ruby", "-c", ctx.test_file }):wait()
    if result.code ~= 0 then
      return false, vim.trim(result.stderr or result.stdout or "")
    end
    local actual = files.read(ctx.test_file)
    local expected = files.read(vim.fs.joinpath(FIXTURES, expected_file))
    if actual ~= expected then
      return false, "content mismatch"
    end
    for _, call in ipairs(run.tool_calls) do
      if call.name == "read_file" then
        return true
      end
    end
    return false, "read_file was not called"
  end,
}
