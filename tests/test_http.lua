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

    Client.static.opts = {
      post = { default = mock_request },
      encode = { default = mock_encode },
      decode = { default = mock_decode },
      schedule = { default = mock_schedule },
    }

    local cb = stub.new()

    adapter = require("codecompanion.adapters").new(adapter)

    Client.new({ adapter = adapter }):request({}, { callback = cb })

    assert.stub(mock_request).was_called(1)
  end)

  it("substitutes variables", function()
    local mock_request = stub.new().returns(nil)

    Client.static.opts = {
      post = { default = mock_request },
      encode = { default = stub.new().returns("{}") },
    }

    adapter = require("codecompanion.adapters").new(adapter)

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

  -- tests for handlers.set_form
  it("uses set_form handler to provide form data", function()
    local mock_request = stub.new().returns(nil)
    local form_data = { form_field1 = "value1", form_field2 = "value2" }

    -- Create adapter with set_form handler
    local test_adapter = vim.deepcopy(adapter)
    test_adapter.handlers.set_form = function(self, payload)
      return form_data
    end

    Client.static.opts = {
      post = { default = mock_request },
      encode = { default = stub.new().returns("{}") },
    }

    test_adapter = require("codecompanion.adapters").new(test_adapter)

    Client.new({ adapter = test_adapter }):request({}, { callback = stub.new() })

    assert.stub(mock_request).was_called(1)
    local request_args = mock_request.calls[1].refs[1]

    -- Verify form data is passed to the request
    -- The request_opts should include form field with filenames
    assert.not_nil(request_args.form)
    -- We can't directly compare the form values since they're converted to filenames
    -- But we can check that the keys match
    assert.equal(vim.tbl_count(request_args.form), vim.tbl_count(form_data))
    for k, _ in pairs(form_data) do
      assert.not_nil(request_args.form[k])
    end
  end)

  it("uses tempfiles to handle set_form data", function()
    local mock_request = stub.new().returns(nil)
    local form_data = { form_field1 = "value1", form_field2 = "value2" }

    -- Create adapter with set_form handler
    local test_adapter = vim.deepcopy(adapter)
    test_adapter.handlers.set_form = function(self, payload)
      return form_data
    end

    -- Mock the Path functionality to avoid actual file creation
    local original_path_new = require("plenary.path").new
    local created_files = {}
    local path_mocks = {}

    require("plenary.path").new = function(filename)
      -- Create a unique mock path for each call
      local mock_path = "mock_path_" .. #created_files + 1
      local mock = {
        filename = mock_path,
        write = stub.new(),
        rm = stub.new(),
      }
      table.insert(created_files, mock)
      return mock
    end

    -- Mock tempname to return predictable values
    local original_tempname = vim.fn.tempname
    local tempname_counter = 0
    vim.fn.tempname = function()
      tempname_counter = tempname_counter + 1
      return "temp_file_" .. tempname_counter
    end

    Client.static.opts = {
      post = { default = mock_request },
      encode = { default = stub.new().returns("{}") },
    }

    test_adapter = require("codecompanion.adapters").new(test_adapter)

    Client.new({ adapter = test_adapter }):request({}, { callback = stub.new() })

    -- Restore original functions
    require("plenary.path").new = original_path_new
    vim.fn.tempname = original_tempname

    assert.stub(mock_request).was_called(1)
    local request_args = mock_request.calls[1].refs[1]

    -- Verify form exists
    assert.not_nil(request_args.form)

    -- Form keys should match
    assert.equal(vim.tbl_count(request_args.form), vim.tbl_count(form_data))

    -- For each field in form_data, there should be a corresponding entry in request_args.form
    for field_name, _ in pairs(form_data) do
      -- The value should be a file reference
      assert.not_nil(request_args.form[field_name])
      -- The value should start with < (file input for curl)
      assert.equals("<", request_args.form[field_name]:sub(1, 1))
    end

    -- Check that each created file had write called on it
    for _, mock_file in ipairs(created_files) do
      assert.stub(mock_file.write).was_called(1)
    end
  end)

  it("preserves form values that already reference files with set_form", function()
    local mock_request = stub.new().returns(nil)

    -- Form with values that already reference files with @ and < prefixes
    local form_data = {
      messages = "@file.txt",
      message2 = "<file2.txt",
    }

    -- Create adapter with set_form handler that returns file references
    local test_adapter = vim.deepcopy(adapter)
    test_adapter.handlers.set_form = function(self, payload)
      return form_data
    end

    Client.static.opts = {
      post = { default = mock_request },
      encode = { default = stub.new().returns("{}") },
    }

    test_adapter = require("codecompanion.adapters").new(test_adapter)

    Client.new({ adapter = test_adapter }):request({}, { callback = stub.new() })

    assert.stub(mock_request).was_called(1)
    local request_args = mock_request.calls[1].refs[1]

    -- The form object exists in the request
    assert.not_nil(request_args.form)

    -- The form fields should be passed through directly without modification
    assert.equal(form_data.message2, request_args.form.message2)
    assert.equal(form_data.messages, request_args.form.messages)
    assert.equal(form_data.message2, request_args.form.message2)
  end)

  it("handles nil set_form handler", function()
    local mock_request = stub.new().returns(nil)

    -- Create adapter without set_form handler
    local test_adapter = vim.deepcopy(adapter)
    test_adapter.handlers.set_form = nil

    Client.static.opts = {
      post = { default = mock_request },
      encode = { default = stub.new().returns("{}") },
    }

    test_adapter = require("codecompanion.adapters").new(test_adapter)

    Client.new({ adapter = test_adapter }):request({}, { callback = stub.new() })

    assert.stub(mock_request).was_called(1)
    local request_args = mock_request.calls[1].refs[1]

    -- Verify form is nil when handler is not present
    assert.is_nil(request_args.form)
  end)

  -- tests for handlers.modify_request_opts
  it("uses modify_request_opts handler to modify request options", function()
    local mock_request = stub.new().returns(nil)

    -- Create adapter with modify_request_opts handler
    local test_adapter = vim.deepcopy(adapter)
    test_adapter.handlers.modify_request_opts = function(self, payload, request_opts)
      request_opts.url = "http://modified.example.com/api"
      request_opts.headers.Authorization = "Bearer modified_token"
      return request_opts
    end

    Client.static.opts = {
      post = { default = mock_request },
      encode = { default = stub.new().returns("{}") },
    }

    test_adapter = require("codecompanion.adapters").new(test_adapter)

    Client.new({ adapter = test_adapter }):request({}, { callback = stub.new() })

    assert.stub(mock_request).was_called(1)
    local request_args = mock_request.calls[1].refs[1]

    -- Verify request options were modified
    assert.equal(request_args.url, "http://modified.example.com/api")
    assert.equal(request_args.headers.Authorization, "Bearer modified_token")
  end)

  it("handles nil modify_request_opts handler", function()
    local mock_request = stub.new().returns(nil)

    -- Create adapter without modify_request_opts handler
    local test_adapter = vim.deepcopy(adapter)
    -- handlers.modify_request_opts is already nil

    Client.static.opts = {
      post = { default = mock_request },
      encode = { default = stub.new().returns("{}") },
    }

    test_adapter = require("codecompanion.adapters").new(test_adapter)

    Client.new({ adapter = test_adapter }):request({}, { callback = stub.new() })

    assert.stub(mock_request).was_called(1)
    local request_args = mock_request.calls[1].refs[1]

    -- Original URL should remain unchanged
    assert.equal(request_args.url, "https://api.openai.com/v1/chat/completions")
  end)
end)
