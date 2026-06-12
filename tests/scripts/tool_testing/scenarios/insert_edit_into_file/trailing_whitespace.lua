-- Markdown file where lines intentionally end with two spaces (hard line break).
-- Model must include the trailing spaces verbatim in old_string; stripping them
-- causes a lookup failure because the tool searches for an exact byte match.

-- Two trailing spaces encoded explicitly so editors can't silently strip them.
local BREAK = "  "

local CONTENT = {
  "# Deployment Guide",
  "",
  "## Prerequisites",
  "",
  "Ensure Docker is installed and running on the host machine." .. BREAK,
  "Check that ports 80 and 443 are available before continuing.",
  "",
  "## Steps",
  "",
  "Pull the latest image from the registry." .. BREAK,
  "Run `docker compose up -d` to start all services.",
  "",
  "## Rollback",
  "",
  "Stop the current containers with `docker compose down`." .. BREAK,
  "Then deploy the previous image tag.",
}

local EXPECTED = {
  "# Deployment Guide",
  "",
  "## Prerequisites",
  "",
  "Ensure Docker is installed and running on the host machine." .. BREAK,
  "Check that ports 80 and 443 are available before continuing.",
  "",
  "## Steps",
  "",
  "Pull the latest image from the registry." .. BREAK,
  "Run `docker compose up -d` to start all services.",
  "",
  "## Rollback",
  "",
  "Stop all running containers with `docker compose down`." .. BREAK,
  "Then deploy the previous image tag.",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: Markdown with intentional trailing two-space line breaks — old_string must preserve trailing spaces exactly",
  name = "Trailing whitespace preserved",
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

In the Rollback section, change "Stop the current containers" to "Stop all running containers". The line ends with two trailing spaces (a Markdown hard line break) — your old_string must include them exactly.

Do not ask for permission — call the tool directly.]],
      ctx.test_file,
      table.concat(CONTENT, "\n")
    )
  end,

  validate = function(ctx, _run)
    -- Read raw bytes to verify trailing spaces are preserved
    local f = assert(io.open(ctx.test_file, "rb"))
    local raw = f:read("*a")
    f:close()

    local actual = vim.fn.readfile(ctx.test_file)
    if actual[#actual] == "" then
      actual[#actual] = nil
    end

    local content_ok = vim.deep_equal(actual, EXPECTED)
    -- Confirm at least two of the trailing-space line breaks survived the edit
    local break_count = select(2, raw:gsub("  \n", ""))
    local breaks_ok = break_count >= 2

    return content_ok and breaks_ok, {
      actual = table.concat(actual, "\n"),
      expected = table.concat(EXPECTED, "\n"),
      trailing_space_line_breaks = break_count,
    }
  end,
}
