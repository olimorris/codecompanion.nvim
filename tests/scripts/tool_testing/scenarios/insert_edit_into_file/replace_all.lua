-- `user_id` appears 12 times. The model must use replace_all = true.

local CONTENT = {
  "local M = {}",
  "",
  "function M.get(user_id)",
  "  return db.find('users', { id = user_id })",
  "end",
  "",
  "function M.update(user_id, data)",
  "  local user = M.get(user_id)",
  "  if not user then",
  "    return nil, 'user ' .. user_id .. ' not found'",
  "  end",
  "  return db.update('users', { id = user_id }, data)",
  "end",
  "",
  "function M.delete(user_id)",
  "  return db.delete('users', { id = user_id })",
  "end",
  "",
  "function M.audit(user_id, action)",
  "  return db.insert('audit_log', {",
  "    action = action,",
  "    timestamp = os.time(),",
  "    user_id = user_id,",
  "  })",
  "end",
  "",
  "function M.permissions(user_id)",
  "  return db.find_all('permissions', { user_id = user_id })",
  "end",
  "",
  "return M",
}

local EXPECTED = {
  "local M = {}",
  "",
  "function M.get(account_id)",
  "  return db.find('users', { id = account_id })",
  "end",
  "",
  "function M.update(account_id, data)",
  "  local user = M.get(account_id)",
  "  if not user then",
  "    return nil, 'user ' .. account_id .. ' not found'",
  "  end",
  "  return db.update('users', { id = account_id }, data)",
  "end",
  "",
  "function M.delete(account_id)",
  "  return db.delete('users', { id = account_id })",
  "end",
  "",
  "function M.audit(account_id, action)",
  "  return db.insert('audit_log', {",
  "    action = action,",
  "    timestamp = os.time(),",
  "    account_id = account_id,",
  "  })",
  "end",
  "",
  "function M.permissions(account_id)",
  "  return db.find_all('permissions', { account_id = account_id })",
  "end",
  "",
  "return M",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: rename identifier appearing 12 times — requires replace_all = true",
  name = "Replace all occurrences",
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

Rename every occurrence of `user_id` to `account_id` throughout the entire file. The identifier appears 12 times — use `replace_all = true` so all occurrences are replaced in a single edit.

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
    local content = table.concat(actual, "\n")
    local old_count = select(2, content:gsub("user_id", ""))
    local new_count = select(2, content:gsub("account_id", ""))
    local ok = old_count == 0 and new_count >= 10
    return ok,
      {
        actual = content,
        expected = table.concat(EXPECTED, "\n"),
        old_occurrences_remaining = old_count,
        new_occurrences = new_count,
      }
  end,
}
