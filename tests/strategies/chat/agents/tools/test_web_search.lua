local assert = require("luassert")
local client = require("codecompanion.http")
local h = require("tests.helpers")
local match = require("luassert.match")
local spy = require("luassert.spy")

local ClientMock = {
  request = spy.new(function(_) end),
}

local client_mock = {
  new = spy.new(function(_)
    return ClientMock
  end),
}

local mock_adapter

local original_pcall = _G.pcall
local original_new = client.new

local mock_pcall = function(_)
  return true, mock_adapter
end

local web_search = require("codecompanion.strategies.chat.agents.tools.web_search")

describe("Web Search Tool", function()
  before_each(function()
    mock_adapter = {
      name = "mock_adapter",
    }

    _G.pcall = mock_pcall
    client.new = client_mock.new
  end)

  after_each(function()
    _G.pcall = original_pcall
    client.new = original_new
  end)

  it("makes a HTTP request", function()
    local mock_agent = {
      tool = {
        request = {
          action = { query = "Neovim latest version" },
        },
        opts = {
          adapter = "mock_adapter",
          opts = {
            time_range = "year",
          },
        },
        cmds = {},
      },
    }

    web_search.handlers.setup(mock_agent)

    local new_call = client_mock.new.calls[1].refs[1]
    local request_call = ClientMock.request.calls[1].refs[2]

    assert.spy(client_mock.new).was.called_with(match.is_table())
    h.eq(new_call.adapter, mock_adapter)
    h.eq(request_call.query, mock_agent.tool.request.action.query)
  end)
end)
