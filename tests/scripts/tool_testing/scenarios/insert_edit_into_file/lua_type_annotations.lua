-- LuaCATS annotations (---@class, ---@field, ---@param) must appear verbatim in old_string.
-- Models sometimes omit or mangle annotation prefixes.

local CONTENT = {
  "---@class HttpClient",
  "---@field base_url string",
  "---@field headers table<string, string>",
  "---@field timeout integer",
  "",
  "---@param base_url string",
  "---@param opts? { timeout?: integer }",
  "---@return HttpClient",
  "local function new(base_url, opts)",
  "  return {",
  "    base_url = base_url,",
  "    headers = {},",
  "    timeout = opts and opts.timeout or 30,",
  "  }",
  "end",
  "",
  "---@param client HttpClient",
  "---@param path string",
  "---@return string",
  "local function get_url(client, path)",
  "  return client.base_url .. path",
  "end",
  "",
  "return { get_url = get_url, new = new }",
}

local EXPECTED = {
  "---@class HttpClient",
  "---@field auth_token string?",
  "---@field base_url string",
  "---@field headers table<string, string>",
  "---@field timeout integer",
  "",
  "---@param base_url string",
  "---@param opts? { timeout?: integer }",
  "---@return HttpClient",
  "local function new(base_url, opts)",
  "  return {",
  "    auth_token = nil,",
  "    base_url = base_url,",
  "    headers = {},",
  "    timeout = opts and opts.timeout or 30,",
  "  }",
  "end",
  "",
  "---@param client HttpClient",
  "---@param path string",
  "---@return string",
  "local function get_url(client, path)",
  "  return client.base_url .. path",
  "end",
  "",
  "return { get_url = get_url, new = new }",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: LuaCATS annotations in old_string — ---@field prefix must be exact",
  name = "Lua type annotations",
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

Make two changes in a single tool call:
1. Add `---@field auth_token string?` to the `HttpClient` class (insert it as the second field, after `---@class HttpClient` and before `---@field base_url`)
2. Add `auth_token = nil,` as the first field in the return table of `new` (before `base_url`)

The annotation lines begin with `---@` — your old_string must include these prefixes exactly.

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
