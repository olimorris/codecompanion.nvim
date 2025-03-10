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

return H
