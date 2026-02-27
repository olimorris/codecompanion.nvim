local h = require("tests.helpers")

local T = MiniTest.new_set()
local child = MiniTest.new_child_neovim()

T["Utils"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        tokens = require('codecompanion.utils.tokens')
      ]])
    end,
    post_once = child.stop,
  },
})

T["Utils"]["calculate()"] = MiniTest.new_set()

T["Utils"]["calculate()"]["returns 0 for nil/empty/non-string"] = function()
  h.eq(0, child.lua([[return tokens.calculate(nil)]]))
  h.eq(0, child.lua([[return tokens.calculate("")]]))
  h.eq(0, child.lua([[return tokens.calculate(123)]]))
  h.eq(0, child.lua([[return tokens.calculate({})]]))
end

T["Utils"]["calculate()"]["counts alphabetic runs with default weight"] = function()
  -- "test" = 4 chars, ceil(4/6) = 1
  h.eq(1, child.lua([[return tokens.calculate("test")]]))
  -- "testing" = 7 chars, ceil(7/6) = 2
  h.eq(2, child.lua([[return tokens.calculate("testing")]]))
end

T["Utils"]["calculate()"]["counts digit runs as 1 token each"] = function()
  h.eq(1, child.lua([[return tokens.calculate("12")]]))
  h.eq(1, child.lua([[return tokens.calculate("1234")]]))
  h.eq(1, child.lua([[return tokens.calculate("123456789")]]))
end

T["Utils"]["calculate()"]["whitespace contributes 0 tokens"] = function()
  h.eq(0, child.lua([[return tokens.calculate("      ")]]))
end

T["Utils"]["calculate()"]["counts punctuation runs as ceil(len/2)"] = function()
  -- "!!!" = 3 chars, ceil(3/2) = 2
  h.eq(2, child.lua([[return tokens.calculate("!!!")]]))
  -- "...." = 4 chars, ceil(4/2) = 2
  h.eq(2, child.lua([[return tokens.calculate("....")]]))
end

T["Utils"]["calculate()"]["handles mixed content deterministically"] = function()
  -- "Hello" ceil(5/6)=1, " " 0, "123" numeric=1, " " 0, "!!" ceil(2/2)=1 → 3
  local result = child.lua([[return tokens.calculate("Hello 123 !!")]])
  h.eq(3, result)
end

T["Utils"]["calculate()"]["supports custom opts"] = function()
  local result = child.lua([[
    return tokens.calculate("abcdefgh", {
      alpha_chars_per_token = 8,
    })
  ]])
  h.eq(1, result)
end

T["Utils"]["calculate()"]["is monotonic for appended ASCII text"] = function()
  local base = child.lua([[return tokens.calculate("Hello")]])
  local extended = child.lua([[return tokens.calculate("Hello world")]])
  h.eq(true, extended >= base)
end

T["Utils"]["calculate()"]["handles non-ascii bytes without errors"] = function()
  local result = child.lua([[return tokens.calculate("Hello 👋 世界")]])
  h.eq(true, result >= 1)
end

T["Utils"]["get_tokens()"] = MiniTest.new_set()

T["Utils"]["get_tokens()"]["returns 0 for nil/empty list"] = function()
  h.eq(0, child.lua([[return tokens.get_tokens(nil)]]))
  h.eq(0, child.lua([[return tokens.get_tokens({})]]))
end

T["Utils"]["get_tokens()"]["sums token counts from message.content"] = function()
  local result = child.lua([[
    return tokens.get_tokens({
      { role = "user", content = "test" },
      { role = "assistant", content = "1234" },
    }, { message_overhead = 0 })
  ]])
  -- "test" = 1, "1234" = 1 (numeric run)
  h.eq(2, result)
end

T["Utils"]["get_tokens()"]["accepts plain string entries"] = function()
  local result = child.lua([[
    return tokens.get_tokens({ "test", "12" }, { message_overhead = 0 })
  ]])
  h.eq(2, result)
end

T["Utils"]["get_tokens()"]["skips invalid/non-string content"] = function()
  local result = child.lua([[
    return tokens.get_tokens({
      { content = "test" },
      { content = nil },
      { content = 42 },
      {},
    }, { message_overhead = 0 })
  ]])
  h.eq(1, result)
end

T["Utils"]["get_tokens()"]["applies message overhead per counted message"] = function()
  local result = child.lua([[
    return tokens.get_tokens({
      { content = "test" },
      { content = "12" },
    }, { message_overhead = 3 })
  ]])
  h.eq(8, result)
end

T["Utils"]["benchmark()"] = MiniTest.new_set()

T["Utils"]["benchmark()"]["calculate() throughput metrics"] = function()
  local result = child.lua([[
    local uv = vim.uv or vim.loop
    local msg = string.rep("Hello 123 !! ", 200) .. "👋世界"
    local iterations = 10000

    -- Warm-up
    for _ = 1, 1000 do
      tokens.calculate(msg)
    end

    local start = uv.hrtime()
    local checksum = 0
    for _ = 1, iterations do
      checksum = checksum + tokens.calculate(msg)
    end
    local elapsed_ns = uv.hrtime() - start
    local elapsed_ms = elapsed_ns / 1e6
    local per_call_us = (elapsed_ns / iterations) / 1e3

    return {
      elapsed_ms = elapsed_ms,
      per_call_us = per_call_us,
      checksum = checksum,
      iterations = iterations,
    }
  ]])

  -- Sanity: avoid dead-code elimination style bugs.
  h.eq(true, result.checksum > 0)
  h.eq(10000, result.iterations)

  -- Soft upper bound (very generous; intended to catch extreme regressions only).
  -- Adjust if your CI machines are slower/faster.
  h.eq(true, result.per_call_us < 200)

  -- Optional visibility in test output.
  MiniTest.add_note(
    string.format(
      "tokens.calculate benchmark: %.2fms total, %.2fμs/call (%d iterations)",
      result.elapsed_ms,
      result.per_call_us,
      result.iterations
    )
  )
end

T["Utils"]["benchmark()"]["get_tokens() throughput metrics"] = function()
  local result = child.lua([[
    local uv = vim.uv or vim.loop

    local messages = {}
    for i = 1, 200 do
      messages[i] = {
        role = (i % 2 == 0) and "user" or "assistant",
        content = "Message " .. i .. ": " .. string.rep("abc123 ", 20),
      }
    end

    local iterations = 2000

    -- Warm-up
    for _ = 1, 200 do
      tokens.get_tokens(messages, { message_overhead = 0 })
    end

    local start = uv.hrtime()
    local checksum = 0
    for _ = 1, iterations do
      checksum = checksum + tokens.get_tokens(messages, { message_overhead = 0 })
    end
    local elapsed_ns = uv.hrtime() - start
    local elapsed_ms = elapsed_ns / 1e6
    local per_call_us = (elapsed_ns / iterations) / 1e3

    return {
      elapsed_ms = elapsed_ms,
      per_call_us = per_call_us,
      checksum = checksum,
      iterations = iterations,
    }
  ]])

  h.eq(true, result.checksum > 0)
  h.eq(2000, result.iterations)
  h.eq(true, result.per_call_us < 1500)

  MiniTest.add_note(
    string.format(
      "tokens.get_tokens benchmark: %.2fms total, %.2fμs/call (%d iterations)",
      result.elapsed_ms,
      result.per_call_us,
      result.iterations
    )
  )
end

return T
