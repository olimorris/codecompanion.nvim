-- JSON config with "timeout" appearing three times at different nesting levels.
-- Model must use surrounding context to target only the http.timeout value.

local CONTENT = {
  "{",
  '  "database": {',
  '    "host": "localhost",',
  '    "port": 5432,',
  '    "timeout": 30,',
  '    "pool": {',
  '      "min": 2,',
  '      "max": 10,',
  '      "timeout": 5000',
  "    }",
  "  },",
  '  "http": {',
  '    "host": "0.0.0.0",',
  '    "port": 8080,',
  '    "timeout": 30,',
  '    "keepalive": true',
  "  },",
  '  "cache": {',
  '    "ttl": 300,',
  '    "timeout": 10',
  "  }",
  "}",
}

local EXPECTED = {
  "{",
  '  "database": {',
  '    "host": "localhost",',
  '    "port": 5432,',
  '    "timeout": 30,',
  '    "pool": {',
  '      "min": 2,',
  '      "max": 10,',
  '      "timeout": 5000',
  "    }",
  "  },",
  '  "http": {',
  '    "host": "0.0.0.0",',
  '    "port": 8080,',
  '    "timeout": 60,',
  '    "keepalive": true',
  "  },",
  '  "cache": {',
  '    "ttl": 300,',
  '    "timeout": 10',
  "  }",
  "}",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = 'insert_edit_into_file: "timeout" appears 3× at different nesting levels — model must anchor on http context to target the right one',
  name = "JSON editing with repeated keys",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".json"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[Use @{insert_edit_into_file} to edit the file at `%s`.

Current content:
```json
%s
```

Change the HTTP server timeout from `30` to `60`. Note that `"timeout"` appears in multiple sections — only the one under `"http"` should change.

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
