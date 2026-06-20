local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "json_editing.json.input"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Edit one of three identically-named keys, identified by its nesting context",
  name = "JSON editing with repeated keys",
  tools = { "insert_edit_into_file" },

  setup = function()
    local input_path = vim.fs.joinpath(FIXTURES, input_file)
    local test_file = vim.fn.tempname() .. ".json"
    files.write_to_path(test_file, files.read(input_path))
    return { input_path = input_path, test_file = test_file }
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
      files.read(ctx.input_path)
    )
  end,

  test = function(ctx)
    if vim.fn.executable("python3") == 0 then
      return false, "python3 not available"
    end
    local result = vim
      .system({
        "python3",
        "-c",
        string.format("import json; d=json.load(open('%s')); print(d['http']['timeout'])", ctx.test_file),
      })
      :wait()
    if result.code ~= 0 then
      local first_line = vim.split(vim.trim(result.stderr or ""), "\n")[1] or ""
      return false, "invalid JSON: " .. first_line
    end
    local output = vim.trim(result.stdout)
    return output == "60", output ~= "60" and "expected http.timeout=60, got: " .. output or nil
  end,
}
