-- A unified diff file. Every context line starts with a space, changes with + or -.
-- The model must include the correct sigil prefix in old_string.

local CONTENT = {
  "--- a/src/auth.py",
  "+++ b/src/auth.py",
  "@@ -1,14 +1,16 @@",
  " import hashlib",
  " import secrets",
  " import time",
  " ",
  " ",
  " def generate_token(user_id):",
  "-    raw = f\"{user_id}:{time.time()}\"",
  "-    return hashlib.md5(raw.encode()).hexdigest()",
  "+    raw = f\"{user_id}:{secrets.token_hex(16)}\"",
  "+    return hashlib.sha256(raw.encode()).hexdigest()",
  " ",
  " ",
  " def verify_token(token, user_id, max_age=3600):",
  "-    expected = generate_token(user_id)",
  "-    return token == expected",
  "+    # Note: this implementation does not check token age",
  "+    return secrets.compare_digest(token, generate_token(user_id))",
}

local EXPECTED = {
  "--- a/src/auth.py",
  "+++ b/src/auth.py",
  "@@ -1,14 +1,16 @@",
  " import hashlib",
  " import secrets",
  " import time",
  " ",
  " ",
  " def generate_token(user_id):",
  "-    raw = f\"{user_id}:{time.time()}\"",
  "-    return hashlib.md5(raw.encode()).hexdigest()",
  "+    raw = f\"{user_id}:{secrets.token_hex(16)}\"",
  "+    return hashlib.sha256(raw.encode()).hexdigest()",
  " ",
  " ",
  " def verify_token(token, user_id, max_age=86400):",
  "-    expected = generate_token(user_id)",
  "-    return token == expected",
  "+    # Note: this implementation does not check token age",
  "+    return secrets.compare_digest(token, generate_token(user_id))",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: unified diff file — old_string must include the leading space/+/- sigil on each line",
  name = "Diff file edit",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".diff"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[Use @{insert_edit_into_file} to edit the file at `%s`.

Current content:
```diff
%s
```

Change the `max_age` default in the `verify_token` context line from `3600` to `86400`. This is a context line in the diff (it starts with a space, not + or -).

The old_string must include the leading space character that marks it as a diff context line.

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
