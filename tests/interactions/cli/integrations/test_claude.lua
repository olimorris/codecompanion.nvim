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

        _G.notifications = {}
        require("codecompanion.utils").notify = function(message)
          table.insert(_G.notifications, message)
        end
        cli = require("codecompanion.interactions.cli").create()
      ]])
    end,
    post_once = child.stop,
  },
})

---Start the hook script as Claude Code would, against the child Neovim
---@param opts { action: string, stdin: table, tmpdir?: string }
---@return vim.SystemObj
local function start_hook(opts)
  return vim.system({ "sh", SCRIPT, opts.action }, {
    env = {
      CODECOMPANION_CLI_BUFNR = tostring(child.lua_get("cli.bufnr")),
      NVIM = child.lua_get("vim.v.servername"),
      PATH = vim.env.PATH,
      TMPDIR = opts.tmpdir or vim.env.TMPDIR,
    },
    stdin = vim.json.encode(opts.stdin),
    text = true,
  })
end

T["Claude Code hooks"] = new_set()

T["Claude Code hooks"]["reaches Neovim when the temporary directory has an apostrophe in it"] = function()
  local tmpdir = vim.fs.joinpath(vim.fn.tempname(), "it's")
  vim.fn.mkdir(tmpdir, "p")
  start_hook({ action = "done", stdin = {}, tmpdir = tmpdir }):wait(5000)

  child.lua([[vim.wait(500, function() return #_G.notifications > 0 end)]])
  h.eq({ "Claude Code finished" }, child.lua_get("_G.notifications"))
end

T["Claude Code hooks"]["notifies without answering permission requests"] = function()
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
