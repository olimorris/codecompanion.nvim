local assert = require("luassert")
local stub = require("luassert.stub")

local Client

local adapter = {
  name = "TestAdapter",
  url = "https://api.openai.com/v1/${url_value}/completions",
  env = {
    url_value = "chat",
    header_value = "json",
    raw_value = "RAW_VALUE",
  },
  headers = {
    content_type = "application/${header_value}",
  },
  parameters = {
    stream = true,
  },
  raw = {
    "--arg1-${raw_value}",
    "--arg2-${raw_value}",
  },
  handlers = {
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
  schema = {
    model = {
      default = "my_model",
    },
  },
}

describe("Client", function()
  before_each(function()
    -- codecompanion.setup()
    Client = require("codecompanion.http") -- Now that setup has been called, we can require the client
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

    Client.static.methods = {
      post = { default = mock_request },
      encode = { default = mock_encode },
      decode = { default = mock_decode },
      schedule = { default = mock_schedule },
    }

    local cb = stub.new()

    adapter = require("codecompanion.adapters").resolve(adapter)
    Client.new({ adapter = adapter }):request({}, { callback = cb })

    assert.stub(mock_request).was_called(1)
  end)

  it("substitutes variables", function()
    local mock_request = stub.new().returns(nil)

    Client.static.methods = {
      post = { default = mock_request },
      encode = { default = stub.new().returns("{}") },
    }

    adapter = require("codecompanion.adapters").resolve(adapter)
    Client.new({ adapter = adapter }):request({}, { callback = stub.new() })

    assert.stub(mock_request).was_called(1)
    local request_args = mock_request.calls[1].refs[1]

    -- can substitute in 'url'
    assert.equal(request_args.url, "https://api.openai.com/v1/chat/completions")

    -- can substitute in 'headers'
    assert.equal(request_args.headers.content_type, "application/json")

    -- can substitute in 'raw'
    local raw_args = request_args.raw
    assert.equal(raw_args[#raw_args - 1], "--arg1-RAW_VALUE")
    assert.equal(raw_args[#raw_args], "--arg2-RAW_VALUE")
  end)
end)
