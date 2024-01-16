local mock = require("luassert.mock")
local stub = require("luassert.stub")
local match = require("luassert.match")
local spy = require("luassert.spy")

local Client = require("codecompanion.client")

local function setup(opts)
  require("codecompanion").setup(opts)
end

describe("Client", function()
  it("should call API correctly when chat is invoked", function()
    local fn_mock = mock(vim.fn, true)
    local log_mock = mock(require("codecompanion.utils.log"), true)
    local autocmds_spy = spy.on(vim.api, "nvim_exec_autocmds")

    local jobstart_stub = stub(fn_mock, "jobstart", function(_, opts)
      local stdout_response = { vim.json.encode("SOME JSON RESPONSE") }

      if opts.on_stdout then
        opts.on_stdout(nil, stdout_response)
      end

      local exit_code = 0
      if opts.on_exit then
        opts.on_exit(nil, exit_code)
      end

      return 1
    end)

    setup({
      base_url = "https://api.example.com",
    })

    local client = Client.new({ secret_key = "TEST_SECRET_KEY" })
    local cb_stub = stub.new()

    client:chat({ messages = { { role = "user", content = "hello" } } }, cb_stub)

    assert.stub(jobstart_stub).was_called(1)
    assert.stub(jobstart_stub).was_called_with(match.is_table(), match.is_table())

    -- It's only called once as the jobstart_stub is stubbed to not fire an event
    assert.spy(autocmds_spy).was_called(1)

    autocmds_spy:revert()
    jobstart_stub:revert()
    mock.revert(fn_mock)
    mock.revert(log_mock)
  end)
end)
