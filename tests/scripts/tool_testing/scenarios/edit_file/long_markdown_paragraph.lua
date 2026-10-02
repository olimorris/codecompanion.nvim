local files = require("codecompanion.utils.files")
local FIXTURES = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local input_file = "long_markdown_paragraph.md.input"
local expected_file = "long_markdown_paragraph.md.expected"

return {
  cleanup = function(ctx)
    files.delete(ctx.test_file)
  end,

  description = "Change one sentence inside a long single-line Markdown paragraph",
  name = "Sentence in a long Markdown paragraph",
  tools = { "edit_file" },

  setup = function()
    local input_path = vim.fs.joinpath(FIXTURES, input_file)
    local test_file = vim.fn.tempname() .. ".md"
    files.write_to_path(test_file, files.read(input_path))
    return { input_path = input_path, test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[Use @{edit_file} to edit the file at `%s`.

Current content:
```markdown
%s
```

In the Caching section, change the sentence "Entries are evicted after 300 seconds unless they are refreshed by a read." to "Entries are evicted after 600 seconds unless they are refreshed by a write." Leave the rest of the paragraph and the Sessions section unchanged.

Do not ask for permission - call the tool directly.]],
      ctx.test_file,
      files.read(ctx.input_path)
    )
  end,

  test = function(ctx)
    local actual = files.read(ctx.test_file)
    local expected = files.read(vim.fs.joinpath(FIXTURES, expected_file))
    if actual ~= expected then
      return false, "content mismatch"
    end
    return true
  end,
}
