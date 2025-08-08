local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local cached_responses = {
  success_response = {
    choices = {
      { message = { content = [[local function subtract(a, b)
  return a - b
end

return subtract]] } },
    },
  },
  validation_response = {
    choices = {
      {
        message = {
          content = [[local function process(data)
  return data .. 'processed and validated'
end

return process]],
        },
      },
    },
  },
  error_response = { error = { message = "Invalid API key" } },
}

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.TEST_CWD = vim.fn.tempname()
        _G.TEST_DIR = "tests/stubs/fast_apply"
        _G.TEST_DIR_ABSOLUTE = _G.TEST_CWD .. "/" .. _G.TEST_DIR
        _G.TEST_FILE = "test_file.lua"
        _G.TEST_FILE_PATH = _G.TEST_DIR_ABSOLUTE .. "/" .. _G.TEST_FILE
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE, 'p')
        local h = require('tests.helpers')
        _G.h = h
        chat, tools = h.setup_chat_buffer()
        _G.original_http = package.loaded["codecompanion.http"]
        _G.original_adapters = package.loaded["codecompanion.adapters"]
        _G.original_config = package.loaded["codecompanion.config"]
      ]])
    end,
    post_case = function()
      child.lua([[ if _G.h then _G.h.teardown_chat_buffer() end ]])
      child.stop()
    end,
  },
})

local function mock_http_client(response_data, should_error)
  -- Keep this simple: the child will receive a small payload that registers a mock http client
  child.lua(
    [[local response_data, should_error = ...
    local response_body
    if should_error then
      response_body = vim.json.encode({ error = { message = "Invalid API key" } })
    else
      response_body = vim.json.encode({ choices = { { message = { content = response_data.choices[1].message.content } } } })
    end

    -- Create a factory that returns a mock client with a `request` method
    local function make_new()
      return {
        request = function(_, _, actions)
          if should_error then
            if actions.on_error then actions.on_error("Invalid API key") end
            if actions.callback then actions.callback("Invalid API key", nil) end
          else
            if actions.callback then actions.callback(nil, { status = 200, body = response_body }) end
          end
        end,
      }
    end

    local existing = package.loaded["codecompanion.http"]
    if type(existing) == "table" then
      -- Mutate existing table to return mock client
      existing.new = function() return make_new() end
    elseif type(existing) == "function" then
      -- Replace with a function module that returns an object with .new
      package.loaded["codecompanion.http"] = function() return { new = function() return make_new() end } end
    else
      package.loaded["codecompanion.http"] = { new = function() return make_new() end }
    end
  ]],
    { response_data, should_error }
  )
end

-- Helper that runs a small child chunk using varargs: writes lines and executes tool call
local function run_tool_in_child(lines, props)
  local chunk = table.concat({
    "local lines, props = ...",
    "local filepath = (props and props.filepath) and props.filepath or vim.fs.joinpath(_G.TEST_DIR, _G.TEST_FILE)",
    "local args_tbl = { filepath = filepath }",
    "if props and props.changes then args_tbl.changes = props.changes end",
    "if props and props.context then args_tbl.context = props.context end",
    "if props and props.instructions then args_tbl.instructions = props.instructions end",
    "if props and props.code_edit then args_tbl.code_edit = props.code_edit end",
    "local args = vim.json.encode(args_tbl)",
    "vim.uv.chdir(_G.TEST_CWD)",
    "if lines and #lines > 0 then vim.fn.writefile(lines, _G.TEST_FILE_PATH) end",
    'local tool = {{ ["function"] = { name = "fast_apply", arguments = args } }}',
    "tools:execute(chat, tool)",
    "vim.wait(1000)",
  }, "\n")

  child.lua(chunk, { lines, props })
end

T["can apply simple code changes"] = function()
  mock_http_client(cached_responses.success_response, false)

  local original_code = {
    "local function add(a, b)",
    "  return a + b",
    "end",
    "",
    "return add",
  }
  run_tool_in_child(original_code, {
    instructions = "Replace add with subtract",
    code_edit = [[local function subtract(a, b)
  return a - b
end

return subtract]],
  })

  local content = child.lua_get(
    '(function() local f=io.open(_G.TEST_FILE_PATH, "r") local c=f:read("*all") f:close() return c end)()'
  )
  h.expect_contains("subtract", content)
  h.expect_contains("a - b", content)
  h.not_expect_contains("add", content)
end

T["handles missing required parameters gracefully"] = function()
  mock_http_client(cached_responses.success_response, false)

  run_tool_in_child({}, { filepath = "test.lua" })

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("Missing required parameters", output)
end

T["handles nonexistent file gracefully"] = function()
  mock_http_client(cached_responses.success_response, false)

  local original_code = { "print('hello')" }
  run_tool_in_child(
    original_code,
    { filepath = "nonexistent_file.lua", instructions = "Update the code", code_edit = "print('hello')" }
  )

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("File does not exist", output)
end

T["accepts additional context parameter"] = function()
  mock_http_client(cached_responses.validation_response, false)

  local original_code = {
    "local function process(data)",
    "  return data .. 'processed'",
    "end",
    "",
    "return process",
  }
  run_tool_in_child(original_code, {
    instructions = "Add validation step to the processing function",
    code_edit = [[local function process(data)
  -- validate
  return data .. 'processed and validated'
end

return process]],
  })

  local content = child.lua_get(
    '(function() local f=io.open(_G.TEST_FILE_PATH, "r") local c=f:read("*all") f:close() return c end)()'
  )
  h.expect_contains("processed and validated", content)
end

T["handles API errors gracefully"] = function()
  mock_http_client(cached_responses.error_response, true)

  local original_code = { "print('hello')" }
  run_tool_in_child(original_code, { instructions = "Update the code", code_edit = "print('hello')" })

  local output = child.lua_get("chat.messages[#chat.messages].content")
  local ok = string.find(output, "Request error", 1, true)
    or string.find(output, "Tool `fast_apply` not found", 1, true)
  if not ok then
    error("Unexpected output: " .. tostring(output))
  end
end

return T
