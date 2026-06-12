-- The string `return nil, "not found"` appears three times.
-- The model must include enough surrounding context to make old_string unique.

local CONTENT = {
  "local M = {}",
  "",
  "local function find_user(id)",
  "  if id == nil or id < 1 then",
  '    return nil, "invalid id"',
  "  end",
  "  local user = db.query('users', id)",
  "  if not user then",
  '    return nil, "not found"',
  "  end",
  "  return user, nil",
  "end",
  "",
  "local function find_post(id)",
  "  if id == nil or id < 1 then",
  '    return nil, "invalid id"',
  "  end",
  "  local post = db.query('posts', id)",
  "  if not post then",
  '    return nil, "not found"',
  "  end",
  "  return post, nil",
  "end",
  "",
  "local function find_comment(id)",
  "  if id == nil or id < 1 then",
  '    return nil, "invalid id"',
  "  end",
  "  local comment = db.query('comments', id)",
  "  if not comment then",
  '    return nil, "not found"',
  "  end",
  "  return comment, nil",
  "end",
  "",
  "return M",
}

local EXPECTED = {
  "local M = {}",
  "",
  "local function find_user(id)",
  "  if id == nil or id < 1 then",
  '    return nil, "invalid id"',
  "  end",
  "  local user = db.query('users', id)",
  "  if not user then",
  '    return nil, "user not found"',
  "  end",
  "  return user, nil",
  "end",
  "",
  "local function find_post(id)",
  "  if id == nil or id < 1 then",
  '    return nil, "invalid id"',
  "  end",
  "  local post = db.query('posts', id)",
  "  if not post then",
  '    return nil, "not found"',
  "  end",
  "  return post, nil",
  "end",
  "",
  "local function find_comment(id)",
  "  if id == nil or id < 1 then",
  '    return nil, "invalid id"',
  "  end",
  "  local comment = db.query('comments', id)",
  "  if not comment then",
  '    return nil, "not found"',
  "  end",
  "  return comment, nil",
  "end",
  "",
  "return M",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: ambiguous old_string — model must include surrounding context to identify the right occurrence",
  name = "Non-unique string",
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

Change the error message in `find_user` only — replace `"not found"` with `"user not found"`. Leave `find_post` and `find_comment` unchanged.

Note: `return nil, "not found"` appears three times in this file. Your old_string must include enough surrounding context (e.g. the `db.query('users', id)` line) to uniquely identify the right location.

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
