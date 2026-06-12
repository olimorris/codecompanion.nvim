-- Go mandates tab indentation. The model must use real tabs in old_string.
-- Two changes: DefaultTimeout and an error message string.

local CONTENT = {
  "package client",
  "",
  "import (",
  '\t"context"',
  '\t"fmt"',
  '\t"net/http"',
  '\t"time"',
  ")",
  "",
  "const (",
  "\tDefaultTimeout = 30 * time.Second",
  "\tMaxRetries     = 3",
  ")",
  "",
  "type Client struct {",
  "\tbaseURL string",
  "\theaders map[string]string",
  "\ttimeout time.Duration",
  "}",
  "",
  "func New(baseURL string) *Client {",
  "\treturn &Client{",
  "\t\tbaseURL: baseURL,",
  "\t\theaders: make(map[string]string),",
  "\t\ttimeout: DefaultTimeout,",
  "\t}",
  "}",
  "",
  "func (c *Client) Get(ctx context.Context, path string) (*http.Response, error) {",
  '\turl := fmt.Sprintf("%s%s", c.baseURL, path)',
  "\treq, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)",
  "\tif err != nil {",
  '\t\treturn nil, fmt.Errorf("creating request: %w", err)',
  "\t}",
  "\tfor k, v := range c.headers {",
  "\t\treq.Header.Set(k, v)",
  "\t}",
  "\treturn http.DefaultClient.Do(req)",
  "}",
}

local EXPECTED = {
  "package client",
  "",
  "import (",
  '\t"context"',
  '\t"fmt"',
  '\t"net/http"',
  '\t"time"',
  ")",
  "",
  "const (",
  "\tDefaultTimeout = 60 * time.Second",
  "\tMaxRetries     = 3",
  ")",
  "",
  "type Client struct {",
  "\tbaseURL string",
  "\theaders map[string]string",
  "\ttimeout time.Duration",
  "}",
  "",
  "func New(baseURL string) *Client {",
  "\treturn &Client{",
  "\t\tbaseURL: baseURL,",
  "\t\theaders: make(map[string]string),",
  "\t\ttimeout: DefaultTimeout,",
  "\t}",
  "}",
  "",
  "func (c *Client) Get(ctx context.Context, path string) (*http.Response, error) {",
  '\turl := fmt.Sprintf("%s%s", c.baseURL, path)',
  "\treq, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)",
  "\tif err != nil {",
  '\t\treturn nil, fmt.Errorf("building request: %w", err)',
  "\t}",
  "\tfor k, v := range c.headers {",
  "\t\treq.Header.Set(k, v)",
  "\t}",
  "\treturn http.DefaultClient.Do(req)",
  "}",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: Go source with mandatory tab indentation — two independent changes",
  name = "Go tabs",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".go"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[Use @{insert_edit_into_file} to make two changes to the Go file at `%s`.

Current content (uses real tab characters for indentation):
```go
%s
```

Changes needed:
1. Change `DefaultTimeout` from `30 * time.Second` to `60 * time.Second`
2. Change the error message from `"creating request: %%w"` to `"building request: %%w"`

Go source files use real tab characters for indentation — your old_string must use real tabs.

Make both changes in a single tool call with two edits. Do not ask for permission — call the tool directly.]],
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
