local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()

        -- Load the cmd_runner module for unit tests
        cmd_runner = require('codecompanion.strategies.chat.tools.catalog.cmd_runner')

        -- Mock global functions and modules
        _G.codecompanion_terminal_preview = {
          bufnr = nil,
          winnr = nil,
          job_id = nil,
          is_active = false
        }

        -- Mock vim functions for testing
        _G.mock_buffers = {}
        _G.mock_windows = {}
        _G.mock_job_id = 1000
        _G.mock_exit_code = 0
        _G.mock_command_output = {"output line 1", "output line 2"}

        -- Helper to create mock tool instance
        function create_mock_tool()
          return {
            args = {},
            cmds = {},
            _terminal_preview = false
          }
        end

        -- Helper to create mock agent/chat
        function create_mock_agent()
          return {
            chat = {
              messages = {},
              terminal_job = nil,
              add_tool_output = function(self, tool, message, user_message)
                table.insert(self.messages, {
                  tool = tool,
                  message = message,
                  user_message = user_message
                })
              end
            }
          }
        end

        _G.output = nil
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["cmd_runner tool"] = function()
  child.lua([[
    require("tests.log")
    local tool = {
      {
        ["function"] = {
          name = "cmd_runner",
          arguments = '{"cmd": "echo hello world"}',
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(200)
  ]])

  expect.reference_screenshot(child.get_screenshot())
end

-- Unit tests for cmd_runner structure and functionality
T["cmd_runner has correct structure"] = function()
  child.lua([[
    structure_info = {
      name = cmd_runner.name,
      has_cmds = type(cmd_runner.cmds) == "table",
      has_schema = type(cmd_runner.schema) == "table",
      has_system_prompt = type(cmd_runner.system_prompt) == "string",
      has_handlers = type(cmd_runner.handlers) == "table",
      has_output = type(cmd_runner.output) == "table"
    }
  ]])

  local structure_info = child.lua_get("structure_info")

  h.eq("cmd_runner", structure_info.name)
  h.eq(true, structure_info.has_cmds)
  h.eq(true, structure_info.has_schema)
  h.eq(true, structure_info.has_system_prompt)
  h.eq(true, structure_info.has_handlers)
  h.eq(true, structure_info.has_output)
end

T["cmd_runner schema is correctly structured"] = function()
  child.lua([[
    schema = cmd_runner.schema

    schema_info = {
      type = schema.type,
      function_name = schema["function"].name,
      function_description = schema["function"].description,
      parameters_type = type(schema["function"].parameters),
      has_required_fields = type(schema["function"].parameters.required) == "table",
      strict = schema["function"].strict
    }

    properties = schema["function"].parameters.properties
    property_info = {
      has_cmd = properties.cmd ~= nil,
      has_flag = properties.flag ~= nil,
      has_terminal_preview = properties.terminal_preview ~= nil,
      cmd_type = properties.cmd.type,
      terminal_preview_type = properties.terminal_preview.type
    }
  ]])

  local schema_info = child.lua_get("schema_info")
  local property_info = child.lua_get("property_info")

  h.eq("function", schema_info.type)
  h.eq("cmd_runner", schema_info.function_name)
  h.eq("table", schema_info.parameters_type)
  h.eq(true, schema_info.has_required_fields)
  h.eq(true, schema_info.strict)

  h.eq(true, property_info.has_cmd)
  h.eq(true, property_info.has_flag)
  h.eq(true, property_info.has_terminal_preview)
  h.eq("string", property_info.cmd_type)
  h.eq("boolean", property_info.terminal_preview_type)
end

T["setup handler creates standard command when terminal_preview is false"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      cmd = "echo hello world",
      flag = nil,
      terminal_preview = false
    }

    mock_tool_obj = {}

    -- Call setup handler
    cmd_runner.handlers.setup(tool, mock_tool_obj)

    setup_result = {
      cmds_count = #tool.cmds,
      terminal_preview_stored = tool._terminal_preview,
      cmd_type = type(tool.cmds[1])
    }
  ]])

  local setup_result = child.lua_get("setup_result")

  h.eq(1, setup_result.cmds_count)
  h.eq(false, setup_result.terminal_preview_stored)
  h.eq("table", setup_result.cmd_type)
end

T["setup handler creates function command when terminal_preview is true"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      cmd = "echo hello world",
      flag = nil,
      terminal_preview = true
    }

    mock_tool_obj = {}

    -- Call setup handler
    cmd_runner.handlers.setup(tool, mock_tool_obj)

    setup_result = {
      cmds_count = #tool.cmds,
      terminal_preview_stored = tool._terminal_preview,
      cmd_type = type(tool.cmds[1])
    }
  ]])

  local setup_result = child.lua_get("setup_result")

  h.eq(1, setup_result.cmds_count)
  h.eq(true, setup_result.terminal_preview_stored)
  h.eq("function", setup_result.cmd_type)
end

T["setup handler handles command with flag"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      cmd = "pytest",
      flag = "testing",
      terminal_preview = false
    }

    mock_tool_obj = {}

    -- Call setup handler
    cmd_runner.handlers.setup(tool, mock_tool_obj)

    setup_result = {
      cmds_count = #tool.cmds,
      has_flag = tool.cmds[1].flag ~= nil,
      flag_value = tool.cmds[1].flag
    }
  ]])

  local setup_result = child.lua_get("setup_result")

  h.eq(1, setup_result.cmds_count)
  h.eq(true, setup_result.has_flag)
  h.eq("testing", setup_result.flag_value)
end

T["output prompt handler returns correct prompt"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = { cmd = "make test" }

    mock_tool_obj = {}

    prompt_text = cmd_runner.output.prompt(tool, mock_tool_obj)
  ]])

  local prompt_text = child.lua_get("prompt_text")

  h.expect_contains("Run the command", prompt_text)
  h.expect_contains("make test", prompt_text)
end

T["output success handler handles empty output"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = { cmd = "silent_command" }
    tool._terminal_preview = false

    mock_tool_obj = {
      chat = create_mock_agent().chat
    }

    mock_cmd = { cmd = "silent_command" }
    empty_stdout = {}

    cmd_runner.output.success(tool, mock_tool_obj, mock_cmd, empty_stdout)

    success_result = {
      message_count = #mock_tool_obj.chat.messages,
      message_content = mock_tool_obj.chat.messages[1].message
    }
  ]])

  local success_result = child.lua_get("success_result")

  h.eq(1, success_result.message_count)
  h.expect_contains("no output from the cmd_runner tool", success_result.message_content)
end

T["output success handler handles normal output"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = { cmd = "echo hello" }
    tool._terminal_preview = false

    mock_tool_obj = {
      chat = create_mock_agent().chat
    }

    mock_cmd = { cmd = "echo hello" }
    stdout = { {"hello", "world"} }

    cmd_runner.output.success(tool, mock_tool_obj, mock_cmd, stdout)

    success_result = {
      message_count = #mock_tool_obj.chat.messages,
      message_content = mock_tool_obj.chat.messages[1].message
    }
  ]])

  local success_result = child.lua_get("success_result")

  h.eq(1, success_result.message_count)
  h.expect_contains("echo hello", success_result.message_content)
  h.expect_contains("```", success_result.message_content)
  h.expect_contains("hello", success_result.message_content)
  h.expect_contains("world", success_result.message_content)
end

T["output error handler formats error output"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = { cmd = "failing_command" }

    mock_tool_obj = {
      chat = create_mock_agent().chat
    }

    mock_cmd = { cmd = "failing_command" }
    stderr = { {"Error: command failed"}, {"Additional error info"} }

    cmd_runner.output.error(tool, mock_tool_obj, mock_cmd, stderr)

    error_result = {
      message_count = #mock_tool_obj.chat.messages,
      llm_message = mock_tool_obj.chat.messages[1].message,
      user_message = mock_tool_obj.chat.messages[1].user_message
    }
  ]])

  local error_result = child.lua_get("error_result")

  h.eq(1, error_result.message_count)
  h.expect_contains("There was an error running", error_result.llm_message)
  h.expect_contains("failing_command", error_result.llm_message)
  h.expect_contains("```txt", error_result.llm_message)
  h.expect_contains("Error: command failed", error_result.llm_message)
  h.expect_contains("error", error_result.user_message)
end

T["handles nil args gracefully"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      cmd = "echo test",
      flag = nil,  -- explicitly nil
      terminal_preview = nil  -- should default to false
    }

    cmd_runner.handlers.setup(tool, {})

    nil_handling = {
      terminal_preview_value = tool._terminal_preview,
      cmds_created = #tool.cmds > 0,
      cmd_type = type(tool.cmds[1])
    }
  ]])

  local nil_handling = child.lua_get("nil_handling")

  h.eq(false, nil_handling.terminal_preview_value)
  h.eq(true, nil_handling.cmds_created)
  h.eq("table", nil_handling.cmd_type)
end

return T
