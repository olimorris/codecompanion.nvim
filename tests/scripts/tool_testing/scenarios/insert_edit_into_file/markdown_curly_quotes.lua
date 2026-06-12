-- Markdown file with Unicode "curly" (smart) quote characters.
-- Models trained on clean text sometimes emit straight quotes in old_string,
-- causing a match failure against the curly-quote bytes on disk.
-- This scenario establishes the baseline failure rate for Stage 3 normalisation.

-- U+201C LEFT DOUBLE QUOTATION MARK  = \xe2\x80\x9c
-- U+201D RIGHT DOUBLE QUOTATION MARK = \xe2\x80\x9d

local CONTENT = {
  "# Release Notes",
  "",
  "## Version 2.0",
  "",
  "This release introduces \xe2\x80\x9cautomatic scaling\xe2\x80\x9d and improves \xe2\x80\x9cerror handling\xe2\x80\x9d across all services.",
  "",
  "The API now returns \xe2\x80\x9cstructured errors\xe2\x80\x9d instead of raw strings.",
  "",
  "Clients should update to handle the new \xe2\x80\x9cerror format\xe2\x80\x9d before upgrading.",
}

local EXPECTED = {
  "# Release Notes",
  "",
  "## Version 2.0",
  "",
  "This release introduces \xe2\x80\x9cauto-scaling\xe2\x80\x9d and improves \xe2\x80\x9cerror handling\xe2\x80\x9d across all services.",
  "",
  "The API now returns \xe2\x80\x9cstructured errors\xe2\x80\x9d instead of raw strings.",
  "",
  "Clients should update to handle the new \xe2\x80\x9cerror format\xe2\x80\x9d before upgrading.",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: Markdown with Unicode curly quotes — old_string must use curly quotes, not straight ASCII quotes",
  name = "Markdown curly quotes",
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

Change \xe2\x80\x9cautomatic scaling\xe2\x80\x9d to \xe2\x80\x9cauto-scaling\xe2\x80\x9d in the first paragraph. Leave all other occurrences unchanged.

Note: the quotes in this file are Unicode curly quotes (\xe2\x80\x9c and \xe2\x80\x9d), not straight ASCII quotes. Your old_string must match them exactly.

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
