local CONTENT = {
  "const API_VERSION = 1;",
  "const MAX_RETRIES = 3;",
  "",
  "function fetchData() {",
  "  console.log('Fetching...');",
  "}",
}

local EXPECTED = {
  "const API_VERSION = 2;",
  "const MAX_RETRIES = 5;",
  "",
  "function fetchData() {",
  "  console.log('Loading data...');",
  "}",
}

return {
  description = "insert_edit_into_file: multiple edits in a single tool call",
  name = "Multiple edits",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".js"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[Use @{insert_edit_into_file} to edit the file at `%s`.

Current content:
```js
%s
```

Changes needed:
1. Change API_VERSION from 1 to 2
2. Change MAX_RETRIES from 3 to 5
3. Change console.log message to 'Loading data...'

Make all three changes in a single tool call with multiple edits. Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      table.concat(CONTENT, "\n")
    )
  end,

  validate = function(ctx, _run)
    local actual = vim.fn.readfile(ctx.test_file)
    if actual[#actual] == "" then actual[#actual] = nil end
    local ok = vim.deep_equal(actual, EXPECTED)
    return ok, { actual = table.concat(actual, "\n"), expected = table.concat(EXPECTED, "\n") }
  end,

  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,
}
