local new_set = MiniTest.new_set
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local SCRIPT = "lua/codecompanion/interactions/cli/integrations/claude.sh"

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        local config = require("codecompanion.config")
        config.interactions.cli.agents = { claude_code = { cmd = "cat", args = {}, description = "Claude Code" } }
        config.interactions.cli.agent = "claude_code"
        h.setup_plugin(config)

        vim.cmd.edit("lua/codecompanion/init.lua")
        vim.api.nvim_win_set_cursor(0, { 12, 0 })
        cli = require("codecompanion.interactions.cli").create()
      ]])
    end,
    post_once = child.stop,
  },
})

---Start the hook script as Claude Code would, against the child Neovim
---@param opts { action: string, stdin: table }
---@return vim.SystemObj
local function start_hook(opts)
  return vim.system({ "sh", SCRIPT, opts.action }, {
    env = {
      CODECOMPANION_CLI_BUFNR = tostring(child.lua_get("cli.bufnr")),
      NVIM = child.lua_get("vim.v.servername"),
      PATH = vim.env.PATH,
      TMPDIR = vim.env.TMPDIR,
    },
    stdin = vim.json.encode(opts.stdin),
    text = true,
  })
end

T["Claude Code hooks"] = new_set()

T["Claude Code hooks"]["a typed prompt carries the user's editor state"] = function()
  local stdout = start_hook({ action = "submitted", stdin = { prompt = "What does this do?" } }):wait(5000).stdout
  h.expect_contains("- Current file: lua/codecompanion/init.lua, cursor on line 12", stdout)
end

T["Claude Code hooks"]["a permission request is left to the terminal, with a notification"] = function()
  child.lua([[
    _G.notifications = {}
    require("codecompanion.utils").notify = function(message)
      table.insert(_G.notifications, message)
    end
  ]])
  start_hook({ action = "submitted", stdin = { prompt = "Run the tests" } }):wait(5000)

  local stdout = start_hook({
    action = "approval_requested",
    stdin = { hook_event_name = "PermissionRequest", tool_name = "Bash", tool_input = { command = "make test" } },
  }):wait(5000).stdout

  h.eq("", stdout)
  child.lua([[vim.wait(500, function() return #_G.notifications > 0 end)]])
  h.eq({ "Claude Code: Permission: Bash: make test" }, child.lua_get("_G.notifications"))
end

return T
