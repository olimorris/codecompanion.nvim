local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        package.preload["plenary.job"] = function()
          return {
            new = function(_, opts)
              return {
                sync = function()
                  if vim.deep_equal(opts.args, { "diff" }) then
                    return { "diff --git a/tracked.txt b/tracked.txt" }
                  end
                  return {}
                end,
              }
            end,
          }
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["get_changed_files"] = new_set()

T["get_changed_files"]["includes unstaged changes when source_control_state is null"] = function()
  child.lua([[
    local builtin = require("codecompanion.interactions.chat.tools.builtin.get_changed_files")
    _G.result = builtin.cmds[1]({ tool = { opts = { max_lines = 100 } } },
      vim.json.decode('{"source_control_state":null}'))
  ]])

  h.eq("success", child.lua_get("_G.result.status"))
  h.expect_contains('getChangedFiles type="unstaged"', child.lua_get("_G.result.data"))
end

return T
