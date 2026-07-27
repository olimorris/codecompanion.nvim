local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        h.setup_plugin()
        builtin = require("codecompanion.interactions.background.builtin.tools_judge")

        -- A background whose `ask` immediately replays a canned result to on_done
        function _G.background_returning(result)
          return {
            ask = function(_, _, opts)
              opts.on_done(result)
            end,
          }
        end

        -- A background whose `ask` immediately fails via on_error
        _G.background_erroring = {
          ask = function(_, _, opts)
            opts.on_error("boom")
          end,
        }

        function _G.judge(background)
          local verdict
          builtin.request(background, { tool_name = "run_command", context = "rm -rf /" }, function(v)
            verdict = v
          end)
          return verdict
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["tools_judge"] = new_set()

T["tools_judge"]["passes a safe verdict through"] = function()
  local verdict = child.lua([[
    return _G.judge(_G.background_returning({
      output = { content = '{"safe":true,"reason":"lists files"}' },
    }))
  ]])

  h.eq(verdict.safe, true)
  h.eq(verdict.reason, "lists files")
end

T["tools_judge"]["passes an unsafe verdict through"] = function()
  local verdict = child.lua([[
    return _G.judge(_G.background_returning({
      output = { content = '{"safe":false,"reason":"deletes everything"}' },
    }))
  ]])

  h.eq(verdict.safe, false)
  h.eq(verdict.reason, "deletes everything")
end

T["tools_judge"]["requires approval when the response is unreadable"] = function()
  local verdict = child.lua([[
    return _G.judge(_G.background_returning({ output = { content = "not json" } }))
  ]])

  h.eq(verdict.safe, false)
end

T["tools_judge"]["requires approval when the request errors"] = function()
  local verdict = child.lua([[return _G.judge(_G.background_erroring)]])

  h.eq(verdict.safe, false)
end

return T
