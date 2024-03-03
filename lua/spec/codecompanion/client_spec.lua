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
  schema = {},
}

describe("Client", function()
  before_each(function()
    codecompanion.setup()
    Client = require("codecompanion.client") -- Now that setup has been called, we can require the client
  end)

  after_each(function()
    _G.codecompanion_jobs = nil
  end)

  it("stream_call should work with mocked dependencies", function()
    local mock_request = stub.new().returns({ args = "mocked args" })
    local mock_encode = stub.new().returns("{}")
    local mock_decode = stub.new().returns({ choices = { { finish_reason = nil } } })
    local mock_schedule = stub.new().returns(1)

    -- Mock globals
    _G.codecompanion_jobs = {}

    Client.static.opts = {
      request = { default = mock_request },
      encode = { default = mock_encode },
      decode = { default = mock_decode },
      schedule = { default = mock_schedule },
    }

    local client = Client.new({
      secret_key = "fake_key",
      organization = "fake_org",
    })

    local cb = stub.new()

    client:stream(adapter, {}, 0, cb)

    assert.stub(mock_request).was_called(1)
  end)
end)
