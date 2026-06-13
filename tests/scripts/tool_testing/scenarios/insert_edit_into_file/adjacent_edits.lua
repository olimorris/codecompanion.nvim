-- Three independent edits clustered close together in a config block.
-- All three must land in a single tool call.

local CONTENT = {
  "local config = {",
  "  database = {",
  "    host = 'localhost',",
  "    name = 'myapp_dev',",
  "    pool_size = 5,",
  "    port = 5432,",
  "    ssl = false,",
  "    timeout = 15,",
  "  },",
  "}",
  "",
  "return config",
}

local EXPECTED = {
  "local config = {",
  "  database = {",
  "    host = 'db.production.internal',",
  "    name = 'myapp_prod',",
  "    pool_size = 5,",
  "    port = 5432,",
  "    ssl = true,",
  "    timeout = 15,",
  "  },",
  "}",
  "",
  "return config",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: three adjacent single-line changes in a single tool call",
  name = "Adjacent edits",
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

Make all three changes in a single tool call with three edits:
1. Change `host` from `'localhost'` to `'db.production.internal'`
2. Change `name` from `'myapp_dev'` to `'myapp_prod'`
3. Change `ssl` from `false` to `true`

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
