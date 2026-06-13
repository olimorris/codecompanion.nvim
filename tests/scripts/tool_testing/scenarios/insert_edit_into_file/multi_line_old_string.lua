-- old_string must span an 8-line block to be unique.
-- Single-line substrings like `config.host = "localhost"` appear elsewhere.

local CONTENT = {
  "local function parse_config(raw)",
  "  local config = {}",
  "",
  "  -- parse host",
  "  if raw.host and type(raw.host) == 'string' then",
  "    config.host = raw.host",
  "  else",
  "    config.host = 'localhost'",
  "  end",
  "",
  "  -- parse port",
  "  if raw.port and type(raw.port) == 'number' then",
  "    config.port = raw.port",
  "  else",
  "    config.port = 5432",
  "  end",
  "",
  "  -- parse timeout",
  "  if raw.timeout and type(raw.timeout) == 'number' then",
  "    config.timeout = raw.timeout",
  "  else",
  "    config.timeout = 30",
  "  end",
  "",
  "  return config",
  "end",
  "",
  "return { parse_config = parse_config }",
}

local EXPECTED = {
  "local function parse_config(raw)",
  "  local config = {}",
  "",
  "  -- parse host",
  "  if raw.host and type(raw.host) == 'string' and raw.host ~= '' then",
  "    config.host = raw.host",
  "  else",
  "    config.host = 'localhost'",
  "  end",
  "",
  "  -- parse port",
  "  if raw.port and type(raw.port) == 'number' then",
  "    config.port = raw.port",
  "  else",
  "    config.port = 5432",
  "  end",
  "",
  "  -- parse timeout",
  "  if raw.timeout and type(raw.timeout) == 'number' then",
  "    config.timeout = raw.timeout",
  "  else",
  "    config.timeout = 30",
  "  end",
  "",
  "  return config",
  "end",
  "",
  "return { parse_config = parse_config }",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: old_string spans multiple lines — single-line substrings are not unique enough",
  name = "Multi-line old_string",
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

In the `-- parse host` block, tighten the condition to also reject empty strings: change `raw.host and type(raw.host) == 'string'` to `raw.host and type(raw.host) == 'string' and raw.host ~= ''`.

Only the host block changes — leave port and timeout unchanged. Your old_string will need to span several lines to uniquely identify this block.

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
