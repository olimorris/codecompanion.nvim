local new_set = MiniTest.new_set
local h = require("tests.helpers")

local client = require("codecompanion.http")
local tavily = require("codecompanion.adapters.tavily")
local web_search = require("codecompanion.strategies.chat.agents.tools.web_search")

local T = new_set({
  hooks = {
    pre_case = function()
      T._original_client = client.new
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
    end,

    post_case = function()
      client.new = T._original_client
    end,
  },
})

T["web search tool"] = function()
  local self = {
    tool = tavily,
  }

  local args = {
    query = "Neovim latest version release May 2025",
  }

  local callback = function(result)
    h.eq(result.status, "success")
  end

  web_search.cmds[1](self, args, nil, callback)
end

return T
