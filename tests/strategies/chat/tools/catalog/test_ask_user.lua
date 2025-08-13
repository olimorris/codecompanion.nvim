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

        -- Load the ask_user module for unit tests
        ask_user = require('codecompanion.strategies.chat.tools.catalog.ask_user')

        -- Helper to create mock tool instance
        function create_mock_tool()
          return {
            args = {},
            cmds = {},
            _question_data = nil
          }
        end

        -- Helper to create mock agent/chat
        function create_mock_agent()
          return {
            chat = {
              messages = {},
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
      ]])
    end,
    post_once = child.stop,
  },
})

-- Test tool structure and schema
T["ask_user has correct structure"] = function()
  child.lua([[
    structure_info = {
      name = ask_user.name,
      has_cmds = type(ask_user.cmds) == "table",
      has_schema = type(ask_user.schema) == "table",
      has_system_prompt = type(ask_user.system_prompt) == "string",
      has_handlers = type(ask_user.handlers) == "table",
      has_output = type(ask_user.output) == "table"
    }
  ]])

  local structure_info = child.lua_get("structure_info")

  h.eq("ask_user", structure_info.name)
  h.eq(true, structure_info.has_cmds)
  h.eq(true, structure_info.has_schema)
  h.eq(true, structure_info.has_system_prompt)
  h.eq(true, structure_info.has_handlers)
  h.eq(true, structure_info.has_output)
end

T["ask_user schema is correctly structured"] = function()
  child.lua([[
    schema = ask_user.schema

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
      has_question = properties.question ~= nil,
      has_options = properties.options ~= nil,
      has_context = properties.context ~= nil,
      question_type = properties.question.type,
      options_type = properties.options.type,
      context_type = properties.context.type,
      required_fields = schema["function"].parameters.required
    }
  ]])

  local schema_info = child.lua_get("schema_info")
  local property_info = child.lua_get("property_info")

  h.eq("function", schema_info.type)
  h.eq("ask_user", schema_info.function_name)
  h.eq("table", schema_info.parameters_type)
  h.eq(true, schema_info.has_required_fields)
  h.eq(true, schema_info.strict)

  h.eq(true, property_info.has_question)
  h.eq(true, property_info.has_options)
  h.eq(true, property_info.has_context)
  h.eq("string", property_info.question_type)
  h.eq("array", property_info.options_type)
  h.eq("string", property_info.context_type)

  -- Check required fields
  h.eq(1, #property_info.required_fields)
  h.eq("question", property_info.required_fields[1])
end

T["ask_user system prompt contains essential information"] = function()
  child.lua([[
    prompt = ask_user.system_prompt

    prompt_info = {
      contains_context = string.find(prompt, "CONTEXT") ~= nil,
      contains_when_to_use = string.find(prompt, "WHEN TO USE") ~= nil,
      contains_when_not_to_use = string.find(prompt, "WHEN NOT TO USE") ~= nil,
      contains_examples = string.find(prompt, "EXAMPLES") ~= nil,
      contains_collaboration = string.find(prompt, "COLLABORATION") ~= nil,
      mentions_decision_points = string.find(prompt, "decision points") ~= nil,
      mentions_multiple_approaches = string.find(prompt, "multiple valid approaches") ~= nil,
      length = #prompt
    }
  ]])

  local prompt_info = child.lua_get("prompt_info")

  h.eq(true, prompt_info.contains_context)
  h.eq(true, prompt_info.contains_when_to_use)
  h.eq(true, prompt_info.contains_when_not_to_use)
  h.eq(true, prompt_info.contains_examples)
  h.eq(true, prompt_info.contains_collaboration)
  h.eq(true, prompt_info.mentions_decision_points)
  h.eq(true, prompt_info.mentions_multiple_approaches)
  h.expect_truthy(prompt_info.length > 1000)
end

-- Test setup handler
T["setup handler creates function command"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "Should I refactor this code or rewrite it?",
      options = {"Refactor existing code", "Rewrite from scratch"},
      context = "The current code is complex but functional"
    }

    mock_tool_obj = {}

    -- Call setup handler
    ask_user.handlers.setup(tool, mock_tool_obj)

    setup_result = {
      cmds_count = #tool.cmds,
      cmd_type = type(tool.cmds[1])
    }
  ]])

  local setup_result = child.lua_get("setup_result")

  h.eq(1, setup_result.cmds_count)
  h.eq("function", setup_result.cmd_type)
end

T["setup handler function executes successfully"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "What approach should I take?",
      options = {"Option A", "Option B"},
      context = "This is important"
    }

    agent = create_mock_agent()

    ask_user.handlers.setup(tool, {})

    -- Execute the function command
    local cmd_func = tool.cmds[1]
    local callback_called = false
    local callback_result = nil

    cmd_func(agent, nil, nil, function(result)
      callback_called = true
      callback_result = result
    end)

    -- Wait for async operations
    vim.wait(50)

    execution_result = {
      callback_called = callback_called,
      callback_status = callback_result and callback_result.status or nil,
      has_question_data = tool._question_data ~= nil,
      question_stored = tool._question_data and tool._question_data.question or nil
    }
  ]])

  local execution_result = child.lua_get("execution_result")

  h.eq(true, execution_result.callback_called)
  h.eq("success", execution_result.callback_status)
  h.eq(true, execution_result.has_question_data)
  h.eq("What approach should I take?", execution_result.question_stored)
end

-- Test output handlers
T["output prompt handler formats question with options"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "Which testing strategy should I use?",
      options = {"Unit tests only", "Integration tests only", "Both unit and integration tests"},
      context = "We need good test coverage"
    }

    -- Simulate setup to create question_data
    tool._question_data = {
      question = tool.args.question,
      context = tool.args.context,
      options = tool.args.options,
      formatted_question = string.format("%s\n\nContext: %s\n\nOptions:\n1) %s\n2) %s\n3) %s\n\nYou can select a number or provide your own response.",
        tool.args.question, tool.args.context, tool.args.options[1], tool.args.options[2], tool.args.options[3])
    }

    prompt_text = ask_user.output.prompt(tool, {})
  ]])

  local prompt_text = child.lua_get("prompt_text")

  h.expect_contains("Which testing strategy should I use?", prompt_text)
  h.expect_contains("Context: We need good test coverage", prompt_text)
  h.expect_contains("Options:", prompt_text)
  h.expect_contains("1) Unit tests only", prompt_text)
  h.expect_contains("2) Integration tests only", prompt_text)
  h.expect_contains("3) Both unit and integration tests", prompt_text)
  h.expect_contains("You can select a number", prompt_text)
end

T["output prompt handler formats question without options"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "How should I handle this error case?",
      context = "The API might return null"
    }

    tool._question_data = {
      question = tool.args.question,
      context = tool.args.context,
      options = {},
      formatted_question = string.format("%s\n\nContext: %s", tool.args.question, tool.args.context)
    }

    prompt_text = ask_user.output.prompt(tool, {})
  ]])

  local prompt_text = child.lua_get("prompt_text")

  h.expect_contains("How should I handle this error case?", prompt_text)
  h.expect_contains("Context: The API might return null", prompt_text)
  h.expect_truthy(string.find(prompt_text, "Options:") == nil)
  h.expect_truthy(string.find(prompt_text, "You can select a number") == nil)
end

T["output approved handler processes numbered option selection"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "Choose an approach",
      options = {"Approach A", "Approach B", "Approach C"}
    }

    agent = create_mock_agent()
    mock_cmd = {}
    feedback = "2"  -- User selects option 2

    ask_user.output.approved(tool, agent, mock_cmd, feedback)

    approved_result = {
      message_count = #agent.chat.messages,
      message_content = agent.chat.messages[1].message
    }
  ]])

  local approved_result = child.lua_get("approved_result")

  h.eq(1, approved_result.message_count)
  h.expect_contains("User selected option 2: Approach B", approved_result.message_content)
  h.expect_contains("Question: Choose an approach", approved_result.message_content)
end

T["output approved handler processes custom response"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "What's the best approach?",
      options = {"Option A", "Option B"}
    }

    agent = create_mock_agent()
    mock_cmd = {}
    feedback = "I think we should use a hybrid approach combining both"

    ask_user.output.approved(tool, agent, mock_cmd, feedback)

    approved_result = {
      message_count = #agent.chat.messages,
      message_content = agent.chat.messages[1].message
    }
  ]])

  local approved_result = child.lua_get("approved_result")

  h.eq(1, approved_result.message_count)
  h.expect_contains(
    "User responded: I think we should use a hybrid approach combining both",
    approved_result.message_content
  )
  h.expect_contains("Question: What's the best approach?", approved_result.message_content)
end

T["output approved handler handles empty feedback"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "Should I proceed?"
    }

    agent = create_mock_agent()
    mock_cmd = {}
    feedback = ""  -- Empty response

    ask_user.output.approved(tool, agent, mock_cmd, feedback)

    approved_result = {
      message_count = #agent.chat.messages,
      message_content = agent.chat.messages[1].message
    }
  ]])

  local approved_result = child.lua_get("approved_result")

  h.eq(1, approved_result.message_count)
  h.expect_contains("User approved without specific response", approved_result.message_content)
  h.expect_contains("Question: Should I proceed?", approved_result.message_content)
end

T["output rejected handler formats rejection message"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "Should I delete this file?"
    }

    agent = create_mock_agent()
    mock_cmd = {}
    feedback = "No, that file is still needed"

    ask_user.output.rejected(tool, agent, mock_cmd, feedback)

    rejected_result = {
      message_count = #agent.chat.messages,
      message_content = agent.chat.messages[1].message
    }
  ]])

  local rejected_result = child.lua_get("rejected_result")

  h.eq(1, rejected_result.message_count)
  h.expect_contains("User declined to answer the question: Should I delete this file?", rejected_result.message_content)
  h.expect_contains("with feedback: No, that file is still needed", rejected_result.message_content)
end

T["output rejected handler handles no feedback"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "Should I refactor this?"
    }

    agent = create_mock_agent()
    mock_cmd = {}
    feedback = nil

    ask_user.output.rejected(tool, agent, mock_cmd, feedback)

    rejected_result = {
      message_count = #agent.chat.messages,
      message_content = agent.chat.messages[1].message
    }
  ]])

  local rejected_result = child.lua_get("rejected_result")

  h.eq(1, rejected_result.message_count)
  h.expect_contains("User declined to answer the question: Should I refactor this?", rejected_result.message_content)
  h.expect_truthy(string.find(rejected_result.message_content, "with feedback:") == nil)
end

T["output error handler formats error output"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "What should I do?"
    }

    mock_tool_obj = {
      chat = create_mock_agent().chat
    }

    mock_cmd = {}
    stderr = { {"Error in ask_user"}, {"Additional error info"} }

    ask_user.output.error(tool, mock_tool_obj, mock_cmd, stderr)

    error_result = {
      message_count = #mock_tool_obj.chat.messages,
      llm_message = mock_tool_obj.chat.messages[1].message,
      user_message = mock_tool_obj.chat.messages[1].user_message
    }
  ]])

  local error_result = child.lua_get("error_result")

  h.eq(1, error_result.message_count)
  h.expect_contains("There was an error with the ask_user", error_result.llm_message)
  h.expect_contains("```txt", error_result.llm_message)
  h.expect_contains("Error in ask_user", error_result.llm_message)
  h.expect_contains("ask_user error", error_result.user_message)
end

-- Test edge cases
T["handles invalid option selection gracefully"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "Pick one",
      options = {"A", "B"}
    }

    agent = create_mock_agent()
    mock_cmd = {}
    feedback = "99"  -- Invalid option number

    ask_user.output.approved(tool, agent, mock_cmd, feedback)

    result = {
      message_content = agent.chat.messages[1].message
    }
  ]])

  local result = child.lua_get("result")

  -- Should treat as custom response since option 99 doesn't exist
  h.expect_contains("User responded: 99", result.message_content)
end

T["handles question without context"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "Simple question?",
      options = {"Yes", "No"}
      -- No context provided
    }

    ask_user.handlers.setup(tool, {})

    -- Execute to set up question data
    local cmd_func = tool.cmds[1]
    cmd_func(create_mock_agent(), nil, nil, function() end)

    prompt_text = ask_user.output.prompt(tool, {})
  ]])

  local prompt_text = child.lua_get("prompt_text")

  h.expect_contains("Simple question?", prompt_text)
  h.expect_contains("Options:", prompt_text)
  h.expect_truthy(string.find(prompt_text, "Context:") == nil)
end

-- Test integration workflow
T["complete workflow with options selection"] = function()
  child.lua([[
    tool = create_mock_tool()
    tool.args = {
      question = "How should I handle the failing tests?",
      options = {"Fix the implementation", "Update the tests", "Skip the failing tests"},
      context = "Tests are failing after refactoring"
    }

    agent = create_mock_agent()

    -- Setup
    ask_user.handlers.setup(tool, {})

    -- Execute to prepare question
    local cmd_func = tool.cmds[1]
    local execution_successful = false
    cmd_func(agent, nil, nil, function(result)
      execution_successful = result.status == "success"
    end)
    vim.wait(50)

    -- Get prompt
    prompt = ask_user.output.prompt(tool, {})

    -- Simulate user approval with option selection
    ask_user.output.approved(tool, agent, {}, "1")

    workflow_result = {
      setup_successful = #tool.cmds > 0,
      execution_successful = execution_successful,
      prompt_contains_question = string.find(prompt, "How should I handle the failing tests?") ~= nil,
      prompt_contains_options = string.find(prompt, "1) Fix the implementation") ~= nil,
      response_processed = #agent.chat.messages > 0,
      correct_option_selected = string.find(agent.chat.messages[1].message, "Fix the implementation") ~= nil
    }
  ]])

  local workflow_result = child.lua_get("workflow_result")

  h.eq(true, workflow_result.setup_successful)
  h.eq(true, workflow_result.execution_successful)
  h.eq(true, workflow_result.prompt_contains_question)
  h.eq(true, workflow_result.prompt_contains_options)
  h.eq(true, workflow_result.response_processed)
  h.eq(true, workflow_result.correct_option_selected)
end

return T
