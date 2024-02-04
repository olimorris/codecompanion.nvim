local assert = require("luassert")
local codecompanion = require("codecompanion")
local stub = require("luassert.stub")

local schema
local Client

describe("Client", function()
  before_each(function()
    codecompanion.setup()
    schema = require("codecompanion.schema")
    Client = require("codecompanion.client") -- Now that setup has been called, we can require the client
  end)

  after_each(function()
    schema.static.client_settings = nil
    _G.codecompanion_jobs = nil
  end)

  it("stream_call should work with mocked dependencies", function()
    local mock_request = stub.new().returns({ args = "mocked args" })
    local mock_encode = stub.new().returns("{}")
    local mock_decode = stub.new().returns({ choices = { { finish_reason = nil } } })
    local mock_schedule = stub.new().returns(1)

    -- Mock globals
    _G.codecompanion_jobs = {}

    schema.static.client_settings = {
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

    client:stream_chat({}, 0, cb)

    assert.stub(mock_request).was_called()
    -- assert.stub(cb).was_called()
  end)
end)
