-- Python function with a multi-line docstring.
-- The edit changes a default parameter value and updates the docstring to match.

local CONTENT = {
  "def calculate_moving_average(values, window=7, min_periods=1):",
  '    """',
  "    Calculate the moving average of a numeric series.",
  "",
  "    Args:",
  "        values: list of numeric values",
  "        window: size of the moving window (default: 7)",
  "        min_periods: minimum observations required for a result (default: 1)",
  "",
  "    Returns:",
  "        list of float values, same length as input.",
  "        Positions with insufficient data return None.",
  '    """',
  "    if not values:",
  "        return []",
  "    result = []",
  "    for i, _ in enumerate(values):",
  "        start = max(0, i - window + 1)",
  "        chunk = values[start : i + 1]",
  "        if len(chunk) < min_periods:",
  "            result.append(None)",
  "        else:",
  "            result.append(sum(chunk) / len(chunk))",
  "    return result",
}

local EXPECTED = {
  "def calculate_moving_average(values, window=14, min_periods=1):",
  '    """',
  "    Calculate the moving average of a numeric series.",
  "",
  "    Args:",
  "        values: list of numeric values",
  "        window: size of the moving window (default: 14)",
  "        min_periods: minimum observations required for a result (default: 1)",
  "",
  "    Returns:",
  "        list of float values, same length as input.",
  "        Positions with insufficient data return None.",
  '    """',
  "    if not values:",
  "        return []",
  "    result = []",
  "    for i, _ in enumerate(values):",
  "        start = max(0, i - window + 1)",
  "        chunk = values[start : i + 1]",
  "        if len(chunk) < min_periods:",
  "            result.append(None)",
  "        else:",
  "            result.append(sum(chunk) / len(chunk))",
  "    return result",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: change a default parameter and update the matching docstring line",
  name = "Python docstring update",
  tools = { "insert_edit_into_file" },
  tools_required = { "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".py"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[Use @{insert_edit_into_file} to edit the file at `%s`.

Current content:
```python
%s
```

Change the default window size from 7 to 14 in two places:
1. The function signature: `window=7` → `window=14`
2. The docstring: `(default: 7)` → `(default: 14)`

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
