-- Markdown file with fenced code blocks.
-- Edits target both prose and content inside a YAML fence.

local CONTENT = {
  "# Configuration Guide",
  "",
  "## Database Settings",
  "",
  "Configure the database connection in your config file:",
  "",
  "````yaml",
  "database:",
  "  host: localhost",
  "  name: myapp",
  "  pool_size: 5",
  "  port: 5432",
  "````",
  "",
  "## Cache Settings",
  "",
  "The cache layer uses Redis and defaults to a 5-minute TTL.",
  "",
  "````yaml",
  "cache:",
  "  backend: redis",
  "  host: localhost",
  "  port: 6379",
  "  ttl: 300",
  "````",
  "",
  "## Rate Limits",
  "",
  "The API allows **100 requests per minute** per API key.",
}

local EXPECTED = {
  "# Configuration Guide",
  "",
  "## Database Settings",
  "",
  "Configure the database connection in your config file:",
  "",
  "````yaml",
  "database:",
  "  host: localhost",
  "  name: myapp",
  "  pool_size: 10",
  "  port: 5432",
  "````",
  "",
  "## Cache Settings",
  "",
  "The cache layer uses Redis and defaults to a 1-hour TTL.",
  "",
  "````yaml",
  "cache:",
  "  backend: redis",
  "  host: localhost",
  "  port: 6379",
  "  ttl: 3600",
  "````",
  "",
  "## Rate Limits",
  "",
  "The API allows **100 requests per minute** per API key.",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: Markdown with fenced code blocks — edits target both prose and YAML inside a fence",
  name = "Markdown fenced code",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".md"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[Use @{insert_edit_into_file} to edit the file at `%s`.

Current content:
```markdown
%s
```

Make three changes in a single tool call:
1. Change `pool_size: 5` to `pool_size: 10` inside the database YAML block
2. Change `ttl: 300` to `ttl: 3600` inside the cache YAML block
3. Update the prose sentence about TTL: change `5-minute TTL` to `1-hour TTL`

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
