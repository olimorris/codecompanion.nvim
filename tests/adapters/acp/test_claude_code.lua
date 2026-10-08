local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
    post_case = child.stop,
  },
})

T["Claude Code adapter"] = new_set()

T["Claude Code adapter"]["passes the OAuth token to the agent when it is set"] = function()
  local result = child.lua([[
    vim.env.CLAUDE_CODE_OAUTH_TOKEN = "sk-ant-oat01-test"
    local adapter = require("codecompanion.adapters").resolve("claude_code")
    require("codecompanion.adapters.utils").get_env_vars(adapter)

    local ok = adapter.handlers.setup(adapter)
    return { ok = ok, token = adapter.env_replaced.CLAUDE_CODE_OAUTH_TOKEN }
  ]])

  h.eq({ ok = true, token = "sk-ant-oat01-test" }, result)
end

T["Claude Code adapter"]["does not pass the env var name as the token when it is unset"] = function()
  local result = child.lua([[
    vim.env.CLAUDE_CODE_OAUTH_TOKEN = nil
    local adapter = require("codecompanion.adapters").resolve("claude_code")
    require("codecompanion.adapters.utils").get_env_vars(adapter)

    local ok = adapter.handlers.setup(adapter)
    return { ok = ok, token = adapter.env_replaced.CLAUDE_CODE_OAUTH_TOKEN }
  ]])

  h.eq({ ok = true }, result)
end

return T
