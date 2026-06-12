-- Python file where comment lines have indentation + comment sigil.
-- old_string must include the exact leading spaces and `#` prefix.

local CONTENT = {
  "class Cache:",
  "    def __init__(self, max_size=100):",
  "        self._store = {}",
  "        self._max_size = max_size",
  "        # track access order for LRU eviction",
  "        self._access_order = []",
  "",
  "    def get(self, key):",
  "        # return None for missing keys",
  "        if key not in self._store:",
  "            return None",
  "        # update access order on hit",
  "        self._access_order.remove(key)",
  "        self._access_order.append(key)",
  "        return self._store[key]",
  "",
  "    def set(self, key, value):",
  "        # evict least-recently-used if at capacity",
  "        if len(self._store) >= self._max_size and key not in self._store:",
  "            oldest = self._access_order.pop(0)",
  "            del self._store[oldest]",
  "        self._store[key] = value",
  "        if key in self._access_order:",
  "            self._access_order.remove(key)",
  "        self._access_order.append(key)",
  "",
  "    def clear(self):",
  "        # drop all entries",
  "        self._store = {}",
  "        self._access_order = []",
}

local EXPECTED = {
  "class Cache:",
  "    def __init__(self, max_size=256):",
  "        self._store = {}",
  "        self._max_size = max_size",
  "        # track access order for LRU eviction",
  "        self._access_order = []",
  "",
  "    def get(self, key):",
  "        # return None for missing keys",
  "        if key not in self._store:",
  "            return None",
  "        # update access order on hit",
  "        self._access_order.remove(key)",
  "        self._access_order.append(key)",
  "        return self._store[key]",
  "",
  "    def set(self, key, value):",
  "        # evict least-recently-used entry if at capacity",
  "        if len(self._store) >= self._max_size and key not in self._store:",
  "            oldest = self._access_order.pop(0)",
  "            del self._store[oldest]",
  "        self._store[key] = value",
  "        if key in self._access_order:",
  "            self._access_order.remove(key)",
  "        self._access_order.append(key)",
  "",
  "    def clear(self):",
  "        # drop all entries",
  "        self._store = {}",
  "        self._access_order = []",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "insert_edit_into_file: Python with indented comment lines — old_string must include leading spaces and # sigil exactly",
  name = "Python indented comments",
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

Current content (uses 4-space indentation):
```python
%s
```

Make two changes in a single tool call:
1. Change `max_size=100` to `max_size=256` in `__init__`
2. Change the comment `# evict least-recently-used if at capacity` to `# evict least-recently-used entry if at capacity` in `set`

The file uses 4-space indentation. Comment lines have leading spaces followed by `#` — include them exactly in old_string.

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
