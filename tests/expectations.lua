local H = {}

H.expect = MiniTest.expect --[[@type function]]
H.eq = MiniTest.expect.equality --[[@type function]]
H.not_eq = MiniTest.expect.no_equality --[[@type function]]

--[[@type function]]
H.eq_info = MiniTest.new_expectation(
  -- this exactly like H.eq
  -- but it also takes in 3rd argument for better error message
  "values are equal",
  -- Predicate: returns true if are equal (equality as in minitest)
  function(left, right)
    return vim.deep_equal(left, right)
  end,
  -- Fail context: explains why it failed
  function(left, right, msg)
    return string.format("Left:  %s\nRight: %s\nMsg: %s", vim.inspect(left), vim.inspect(right), msg)
  end
)

--[[@type function]]
H.expect_truthy = MiniTest.new_expectation(
  "value is truthy",
  -- Predicate: returns true if value is not false and not nil
  function(value)
    return value ~= false and value ~= nil
  end,
  -- Fail context: explains why it failed
  function(value)
    return string.format("\nExpected value to be truthy (not false or nil), but got:\n%s", vim.inspect(value))
  end
)

--[[@type function]]
H.expect_starts_with = MiniTest.new_expectation(
  "string starts with",
  function(pattern, str)
    return str:find("^" .. pattern) ~= nil
  end,
  -- Fail context
  function(pattern, str)
    return string.format("\nExpected string to start with:\n%s\n\nObserved string:\n%s", vim.inspect(pattern), str)
  end
)

--[[@type function]]
H.expect_contains = MiniTest.new_expectation("string contains", function(pattern, str)
  return str:find(pattern, 1, true) ~= nil
end, function(pattern, str)
  return string.format("\nExpected string to contain:\n%s\n\nObserved string:\n%s", vim.inspect(pattern), str)
end)

--[[@type function]]
H.expect_match = MiniTest.new_expectation("string matching", function(str, pattern)
  return str:find(pattern) ~= nil
end, function(str, pattern)
  return string.format("Pattern: %s\nObserved string: %s", vim.inspect(pattern), str)
end)

--[[@type function]]
H.expect_tbl_contains = MiniTest.new_expectation(
  "table contains value",
  function(value, tbl)
    -- Helper function to recursively search through nested tables
    local function search(t)
      if type(t) ~= "table" then
        return t == value
      end

      -- Check keys first
      for k, _ in pairs(t) do
        if k == value then
          return true
        end
      end

      -- Then check values and recursively search nested tables
      for _, v in pairs(t) do
        if v == value then
          return true
        elseif type(v) == "table" then
          if search(v) then
            return true
          end
        end
      end

      return false
    end

    return search(tbl)
  end,
  -- Fail context
  function(value, tbl)
    return string.format(
      "\nExpected table to contain value:\n%s\n\nObserved table:\n%s",
      vim.inspect(value),
      vim.inspect(tbl)
    )
  end
)

H.expect_json_equals = MiniTest.new_expectation(
  "JSON equivalence",
  function(expected_json, actual_json)
    -- If both are already tables, compare them directly
    if type(expected_json) == "table" and type(actual_json) == "table" then
      return vim.deep_equal(expected_json, actual_json)
    end

    -- If they're strings, parse them first
    local expected_table, actual_table

    if type(expected_json) == "string" then
      local ok, parsed = pcall(vim.json.decode, expected_json)
      if not ok then
        return false
      end
      expected_table = parsed
    else
      expected_table = expected_json
    end

    if type(actual_json) == "string" then
      local ok, parsed = pcall(vim.json.decode, actual_json)
      if not ok then
        return false
      end
      actual_table = parsed
    else
      actual_table = actual_json
    end

    -- Now compare the parsed tables
    return vim.deep_equal(expected_table, actual_table)
  end,
  -- Fail context
  function(expected_json, actual_json)
    local exp_str = type(expected_json) == "table" and vim.inspect(expected_json) or expected_json
    local act_str = type(actual_json) == "table" and vim.inspect(actual_json) or actual_json

    return string.format("\nExpected JSON equivalence with:\n%s\n\nActual JSON:\n%s", exp_str, act_str)
  end
)

return H
