local fmt = string.format

---@class CodeCompanion.Tool.AskUser: CodeCompanion.Tools.Tool
return {
  name = "ask_user",
  cmds = {
    -- This is dynamically populated via the setup function
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "ask_user",
      description = "Ask the user a question when multiple valid approaches exist or when user input is needed for decision making.",
      parameters = {
        type = "object",
        properties = {
          question = {
            type = "string",
            description = "The question to ask the user. Be clear and specific about what decision needs to be made.",
          },
          options = {
            type = "array",
            items = { type = "string" },
            description = "Optional list of predefined choices. If provided, user can select by number or provide custom response.",
          },
          context = {
            type = "string",
            description = "Additional context about why this decision is needed and what the implications are.",
          },
        },
        required = {
          "question",
        },
        additionalProperties = false,
      },
      strict = true,
    },
  },
  system_prompt = fmt([[# Ask User Tool (`ask_user`)

## CONTEXT
- You have access to an interactive question tool that allows you to ask the user for input when facing decision points.
- Use this tool when there are multiple valid approaches and user expertise/preference is needed.
- This enables collaborative problem-solving rather than making assumptions about user intent.

## WHEN TO USE
- **Multiple Valid Solutions:** When there are several reasonable approaches (e.g., refactor vs rewrite, remove test vs implement feature)
- **Destructive Operations:** Before making potentially unwanted changes (e.g., deleting code, major refactoring)
- **Architectural Decisions:** When design patterns or technology choices affect long-term maintainability
- **Ambiguous Requirements:** When user intent is unclear from the original request
- **Trade-off Decisions:** When there are performance/maintainability/complexity trade-offs to consider

## WHEN NOT TO USE
- **Clear Best Practices:** Don't ask about well-established coding standards
- **Simple Implementation Details:** Don't ask about obvious technical choices
- **Already Specified:** Don't re-ask about things the user has already decided

## RESPONSE FORMAT
- Ask clear, specific questions that help guide the solution
- Provide context about why the decision matters
- Include numbered options when there are clear alternatives
- Allow for custom responses beyond the provided options

## EXAMPLES
Good: "I found failing tests for a missing `validateInput()` function. Should I: 1) Implement the missing function, or 2) Remove the failing tests? The tests suggest input validation was planned but never implemented."

Bad: "What should I do?" (too vague)
Bad: "Should I use camelCase or snake_case?" (established by project conventions)

## COLLABORATION APPROACH
- Present the decision clearly with relevant context
- Explain the implications of different choices
- Respect user expertise and preferences
- Use their input to guide subsequent implementation]]),
  handlers = {
    ---@param self CodeCompanion.Tool.AskUser
    ---@param tool CodeCompanion.Tools The tool object
    setup = function(self, tool)
      local args = self.args

      -- Create a function that will handle the user interaction
      table.insert(self.cmds, function(agent, _, _, cb)
        cb = vim.schedule_wrap(cb)

        -- Format the question with context and options
        local question_text = args.question
        local context_text = args.context or ""
        local options = args.options or {}

        -- Build the formatted question
        local formatted_question = question_text

        if context_text and context_text ~= "" then
          formatted_question = fmt("%s\n\nContext: %s", formatted_question, context_text)
        end

        if #options > 0 then
          formatted_question = formatted_question .. "\n\nOptions:"
          for i, option in ipairs(options) do
            formatted_question = fmt("%s\n%d) %s", formatted_question, i, option)
          end
          formatted_question = formatted_question .. "\n\nYou can select a number or provide your own response."
        end

        -- Store the question data for the output handler to use
        self._question_data = {
          question = args.question,
          context = context_text,
          options = options,
          formatted_question = formatted_question,
        }

        -- Return success to indicate the question is ready to be asked
        cb({
          status = "success",
          data = { formatted_question },
        })
      end)
    end,
  },

  output = {
    ---Prompt the user with the question
    ---@param self CodeCompanion.Tool.AskUser
    ---@param tool CodeCompanion.Tools
    ---@return string
    prompt = function(self, tool)
      local question_data = self._question_data
      if not question_data then
        return "Ask: " .. (self.args.question or "No question provided")
      end

      return question_data.formatted_question
    end,

    ---Handle user's response to the question
    ---@param self CodeCompanion.Tool.AskUser
    ---@param agent CodeCompanion.Tools
    ---@param cmd table
    ---@param feedback? string The user's response
    ---@return nil
    approved = function(self, agent, cmd, feedback)
      local question = self.args.question
      local options = self.args.options or {}
      local user_response = feedback or ""

      -- Parse user response if they selected a numbered option
      local selected_option = nil
      if #options > 0 then
        local option_num = tonumber(user_response:match("^%s*(%d+)"))
        if option_num and option_num >= 1 and option_num <= #options then
          selected_option = options[option_num]
        end
      end

      -- Format the response message
      local response_message
      if selected_option then
        response_message =
          fmt("User selected option %d: %s", tonumber(user_response:match("^%s*(%d+)")), selected_option)
      elseif user_response and user_response ~= "" then
        response_message = fmt("User responded: %s", user_response)
      else
        response_message = "User approved without specific response"
      end

      -- Add context about the original question
      local full_message = fmt("Question: %s\n\n%s", question, response_message)

      agent.chat:add_tool_output(self, full_message)
    end,

    ---Rejection message back to the LLM
    ---@param self CodeCompanion.Tool.AskUser
    ---@param agent CodeCompanion.Tools
    ---@param cmd table
    ---@param feedback? string
    ---@return nil
    rejected = function(self, agent, cmd, feedback)
      local question = self.args.question
      local message = fmt("User declined to answer the question: %s", question)
      if feedback and feedback ~= "" then
        message = message .. fmt(" with feedback: %s", feedback)
      end
      agent.chat:add_tool_output(self, message)
    end,

    ---@param self CodeCompanion.Tool.AskUser
    ---@param tool CodeCompanion.Tools
    ---@param cmd table
    ---@param stderr table The error output
    error = function(self, tool, cmd, stderr)
      local chat = tool.chat
      local errors = vim.iter(stderr):flatten():join("\n")

      local output = [[%s
```txt
%s
```]]

      local llm_output = fmt(output, "There was an error with the ask_user:", errors)
      local user_output = fmt(output, "ask_user error", errors)

      chat:add_tool_output(self, llm_output, user_output)
    end,

    ---@param self CodeCompanion.Tool.AskUser
    ---@param tool CodeCompanion.Tools
    ---@param cmd table The command that was executed
    ---@param stdout table The output from the command
    success = function(self, tool, cmd, stdout)
      -- For ask_user, success means the question was formatted and is ready to be asked
      -- The actual user interaction happens in the approved/rejected handlers
      -- We don't need to add any output here as the prompt will handle the question display
    end,
  },
}

