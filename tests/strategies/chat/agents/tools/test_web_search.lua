local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
  },
})

T["web search tool"] = function()
  local result = child.lua([[
    local client = require("codecompanion.http")
    client.new = function(_)
      return {
        request = function(_, _, opts)
          local lines = vim.fn.readfile("tests/adapters/stubs/output/tavily_search.txt")
          local json_string = table.concat(lines, "\n")
          local tavily_search_stub = vim.json.decode(json_string)
          opts.callback(nil, tavily_search_stub)
        end,
      }
    end

    local tavily = require("codecompanion.adapters.tavily")
    local web_search = require("codecompanion.strategies.chat.agents.tools.web_search")

    local self = {
      tool = tavily,
    }
    local args = {
      query = "Neovim latest version release May 2025",
    }

    local output

    web_search.cmds[1](self, args, nil, function(result)
      output = result.status
    end)

    return output
  ]])

  h.eq("success", result)
end

return T
