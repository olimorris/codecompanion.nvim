-- new_string contains characters that break naive Lua string.gsub replacement:
-- %{...} acts as a gsub pattern class, $1 acts as a capture ref.
-- A correct implementation uses positional string slicing, not gsub.

local CONTENT = {
  "// Template engine utilities",
  "",
  "const ESCAPE_MAP = {",
  "  '&': '&amp;',",
  "  '<': '&lt;',",
  "  '>': '&gt;',",
  "};",
  "",
  "function escapeHtml(str) {",
  "  return str.replace(/[&<>]/g, (char) => ESCAPE_MAP[char] || char);",
  "}",
  "",
  "function formatTemplate(template, vars) {",
  "  return template.replace(/\\$\\{(\\w+)\\}/g, (match, key) => vars[key] ?? match);",
  "}",
  "",
  "module.exports = { escapeHtml, formatTemplate };",
}

local EXPECTED = {
  "// Template engine utilities",
  "",
  "const ESCAPE_MAP = {",
  "  '&': '&amp;',",
  "  '<': '&lt;',",
  "  '>': '&gt;',",
  "};",
  "",
  "function escapeHtml(str) {",
  "  return str.replace(/[&<>]/g, (char) => ESCAPE_MAP[char] || char);",
  "}",
  "",
  "function formatTemplate(template, vars) {",
  "  return template.replace(/%\\{(\\w+)\\}/g, (match, key) => vars[key] ?? match);",
  "}",
  "",
  "module.exports = { escapeHtml, formatTemplate };",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: new_string contains Lua gsub-special characters (%{...}) — tests that replacement uses positional slicing not gsub",
  name = "Special chars in new_string",
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

In `formatTemplate`, change the regex from `\$\{(\w+)\}` (dollar-brace style) to `%%\{(\w+)\}` (percent-brace style). Only the regex pattern changes; the rest of the function stays the same.

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
