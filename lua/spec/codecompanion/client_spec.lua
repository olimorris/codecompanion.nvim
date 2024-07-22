local assert = require("luassert")
local codecompanion = require("codecompanion")
local stub = require("luassert.stub")

local Client

local adapter = {
  name = "TestAdapter",
  url = "https://api.openai.com/v1/chat/completions",
  headers = {
    content_type = "application/json",
  },
  parameters = {
    stream = true,
  },
  callbacks = {
    form_parameters = function()
      return {}
    end,
    form_messages = function()
      return {}
    end,
    is_complete = function()
      return false
    end,
  },
  schema = {},
}

describe("Client", function()
  before_each(function()
    codecompanion.setup()
    Client = require("codecompanion.client") -- Now that setup has been called, we can require the client
  end)

  it("can call API endpoints", function()
    local mock_handler = {
      after = stub.new().returns(nil),
      args = "mocked args",
    }

    local mock_request = stub.new().returns(mock_handler)
    local mock_encode = stub.new().returns("{}")
    local mock_decode = stub.new().returns({ choices = { { finish_reason = nil } } })
    local mock_schedule = stub.new().returns(1)

    Client.static.opts = {
      request = { default = mock_request },
      encode = { default = mock_encode },
      decode = { default = mock_decode },
      schedule = { default = mock_schedule },
    }

    local cb = stub.new()

    adapter = require("codecompanion.adapters").new(adapter)

    Client.new():stream(adapter, {}, 0, cb)

    assert.stub(mock_request).was_called(1)
  end)
end)
