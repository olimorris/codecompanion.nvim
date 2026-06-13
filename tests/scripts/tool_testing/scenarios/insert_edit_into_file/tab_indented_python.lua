-- The file content uses real tab characters for indentation.
-- The model must emit real tabs in old_string — not spaces.

local CONTENT = {
  "class DataProcessor:",
  "\tdef __init__(self, config):",
  "\t\tself.config = config",
  "\t\tself.results = []",
  "\t\tself.errors = []",
  "",
  "\tdef process(self, items):",
  "\t\tfor item in items:",
  "\t\t\tif not item.get('active'):",
  "\t\t\t\tcontinue",
  "\t\t\ttry:",
  "\t\t\t\tresult = self._transform(item)",
  "\t\t\t\tself.results.append(result)",
  "\t\t\texcept Exception as e:",
  "\t\t\t\tself.errors.append({'id': item['id'], 'error': str(e)})",
  "\t\treturn self.results",
  "",
  "\tdef _transform(self, item):",
  "\t\treturn {",
  "\t\t\t'id': item['id'],",
  "\t\t\t'value': item['value'] * 2,",
  "\t\t\t'label': item.get('label', 'unknown'),",
  "\t\t}",
}

local EXPECTED = {
  "class DataProcessor:",
  "\tdef __init__(self, config):",
  "\t\tself.config = config",
  "\t\tself.results = []",
  "\t\tself.errors = []",
  "",
  "\tdef process(self, items):",
  "\t\tfor item in items:",
  "\t\t\tif not item.get('active'):",
  "\t\t\t\tcontinue",
  "\t\t\ttry:",
  "\t\t\t\tresult = self._transform(item)",
  "\t\t\t\tself.results.append(result)",
  "\t\t\texcept Exception as e:",
  "\t\t\t\tself.errors.append({'id': item['id'], 'error': str(e)})",
  "\t\treturn self.results",
  "",
  "\tdef _transform(self, item):",
  "\t\treturn {",
  "\t\t\t'id': item['id'],",
  "\t\t\t'value': item['value'] * self.config.multiplier,",
  "\t\t\t'label': item.get('label', 'unknown'),",
  "\t\t}",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: tab-indented Python — old_string must use real tab characters, not spaces",
  name = "Tab-indented Python",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".py"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
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
