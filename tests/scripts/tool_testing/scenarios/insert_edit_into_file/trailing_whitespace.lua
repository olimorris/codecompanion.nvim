local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "trailing_whitespace.md.input"
local expected_file = "trailing_whitespace.md.expected"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Edit Markdown with intentional trailing two-space line breaks",
  name = "Trailing whitespace preserved",
  tools = { "insert_edit_into_file" },

  setup = function()
    local input_path = vim.fs.joinpath(FIXTURES, input_file)
    local test_file = vim.fn.tempname() .. ".md"
    files.write_to_path(test_file, files.read(input_path))
    return { input_path = input_path, test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[Use @{insert_edit_into_file} to edit the file at `%s`.

Current content:
```markdown
%s
```

In the Rollback section, change "Stop the current containers" to "Stop all running containers". The line ends with two trailing spaces (a Markdown hard line break) — your old_string must include them exactly.

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      files.read(ctx.input_path)
    )
  end,

  test = function(ctx)
    -- Read raw bytes to verify trailing spaces are preserved
    local f = assert(io.open(ctx.test_file, "rb"))
    local raw = f:read("*a")
    f:close()

    local actual = files.read(ctx.test_file)
    local expected = files.read(vim.fs.joinpath(FIXTURES, expected_file))

    local content_ok = actual == expected
    -- Confirm at least two of the trailing-space line breaks survived the edit
    local break_count = select(2, raw:gsub("  \n", ""))
    local breaks_ok = break_count >= 2

    if not content_ok then
      return false, "content mismatch"
    end
    if not breaks_ok then
      return false, "trailing-space line breaks lost"
    end
    return true
  end,
}
