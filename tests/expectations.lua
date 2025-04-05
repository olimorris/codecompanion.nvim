local H = {}

H.expect = MiniTest.expect --[[@type function]]
H.eq = MiniTest.expect.equality --[[@type function]]
H.not_eq = MiniTest.expect.no_equality --[[@type function]]

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

return H
