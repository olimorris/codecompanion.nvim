local CONTENT = {
  "def calculate(x, y):",
  "    return x + y",
}

local EXPECTED = {
  "def calculate(x, y):",
  "    return x * y",
}

return {
  description = "read_file + insert_edit_into_file: read then edit",
  name = "Tool group test",
  tools = { "read_file", "insert_edit_into_file" },
  tools_required = { "read_file", "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".py"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[First use @{read_file} to read the file `%s`, then use @{insert_edit_into_file} to change the calculate function to multiply (x * y) instead of add (x + y).

Read the file first to confirm the exact content before editing. Do not ask for permission — call the tools directly.]],
      ctx.test_file
    )
  end,

  validate = function(ctx, run)
    local actual = vim.fn.readfile(ctx.test_file)
    if actual[#actual] == "" then actual[#actual] = nil end
    local file_ok = vim.deep_equal(actual, EXPECTED)
    local read_was_called = false
    for _, call in ipairs(run.tool_calls) do
      if call.name == "read_file" then
        read_was_called = true
        break
      end
    end
    return file_ok and read_was_called, {
      actual = table.concat(actual, "\n"),
      expected = table.concat(EXPECTED, "\n"),
      read_was_called = read_was_called,
    }
  end,

  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,
}
