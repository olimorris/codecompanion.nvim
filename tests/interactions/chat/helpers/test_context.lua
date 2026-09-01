local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

      child.lua([[
        _G.helpers = require("codecompanion.interactions.chat.helpers.context")
        require("codecompanion").setup(require("tests.config"))
      ]])
    end,
    post_once = child.stop,
  },
})

T["exceeds_input_limit"] = new_set()

T["exceeds_input_limit"]["returns true when the messages exceed the limit"] = function()
  local result = child.lua([[
    return _G.helpers.exceeds_input_limit({
      adapter = { schema = { model = { default = "m", choices = { m = { meta = { context_window = 50 } } } } } },
      messages = {
        { role = "user", content = "hello", _meta = { estimated_tokens = 40 } },
        { role = "user", content = string.rep("word ", 200) },
      },
    })
  ]])

  h.eq(true, result.exceeded)
  h.eq(50, result.input_limit)
  h.expect_truthy(result.token_count > 50)
end

T["exceeds_input_limit"]["prefers the model's prompt limit over its context window"] = function()
  local result = child.lua([[
    return _G.helpers.exceeds_input_limit({
      adapter = {
        schema = {
          model = {
            default = "m",
            choices = { m = { meta = { context_window = 100000, max_prompt_tokens = 50 } } },
          },
        },
      },
      messages = { { role = "user", content = "hello", _meta = { estimated_tokens = 60 } } },
    })
  ]])

  h.eq(true, result.exceeded)
  h.eq(50, result.input_limit)
end

T["estimate_tokens"] = new_set()

T["estimate_tokens"]["trusts stored estimates rather than recomputing from content"] = function()
  local result = child.lua([[
    return _G.helpers.estimate_tokens({ { role = "user", content = "hi", _meta = { estimated_tokens = 90 } } })
  ]])

  h.eq(90, result)
end

T["estimate_tokens"]["calculates for messages that have no stored estimate"] = function()
  local result = child.lua([[
    return _G.helpers.estimate_tokens({ { role = "user", content = string.rep("word ", 200) } })
  ]])

  h.expect_truthy(result > 0)
end

T["estimate_tokens"]["ignores images"] = function()
  local result = child.lua([[
    local tags = require("codecompanion.interactions.shared.tags")

    return _G.helpers.estimate_tokens({
      { role = "user", content = "hello", _meta = { estimated_tokens = 10 } },
      { role = "user", content = string.rep("A", 100000), _meta = { tag = tags.IMAGE, estimated_tokens = 20000 } },
    })
  ]])

  h.eq(10, result)
end

T["truncate_tool_output"] = new_set()

T["truncate_tool_output"]["DOES NOT truncate a tool that is INSIDE the limit"] = function()
  local result = child.lua([[
    return _G.helpers.truncate_tool_output({
      adapter = { schema = { model = { default = "m", choices = { m = { meta = { context_window = 100000 } } } } } },
      content = "a short tool result",
    })
  ]])

  h.eq("a short tool result", result)
end

T["truncate_tool_output"]["truncates a tool that is OUTSIDE the limit"] = function()
  local result = child.lua([[
    return _G.helpers.truncate_tool_output({
      adapter = { schema = { model = { default = "m", choices = { m = { meta = { context_window = 50 } } } } } },
      content = string.rep("word ", 5000),
    })
  ]])

  h.expect_match(result, "^word word")
  h.expect_match(result, "Tool output truncated")
  h.expect_truthy(#result < #string.rep("word ", 5000))
end

T["truncate_tool_output"]["caps at the configured limit when the model's is larger"] = function()
  local result = child.lua([[
    local config = require("codecompanion.config")
    config.interactions.chat.tools.opts.max_output_tokens = 10

    return _G.helpers.truncate_tool_output({
      adapter = { schema = { model = { default = "m", choices = { m = { meta = { context_window = 100000 } } } } } },
      content = string.rep("word ", 500),
    })
  ]])

  h.expect_match(result, "Tool output truncated")
  h.expect_match(result, "over the 10 token limit")
end

T["truncate_tool_output"]["keeps the truncated output and notification under the limit"] = function()
  local result = child.lua([[
    local config = require("codecompanion.config")
    config.interactions.chat.tools.opts.max_output_tokens = 100

    local content = _G.helpers.truncate_tool_output({
      adapter = { schema = { model = { default = "m", choices = { m = { meta = { context_window = 100000 } } } } } },
      content = string.rep("word ", 5000),
    })

    return require("codecompanion.utils.tokens").calculate(content)
  ]])

  h.expect_truthy(result <= 100)
end

return T
