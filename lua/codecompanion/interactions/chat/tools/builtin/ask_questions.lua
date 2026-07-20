local question_prompt = require("codecompanion.interactions.chat.helpers.question_prompt")

local log = require("codecompanion.utils.log")

local fmt = string.format

---Build a formatted response from collected answers
---@param questions table The original questions from the LLM
---@param answers table<string, string> Map of header -> answer
---@return string
local function format_answers(questions, answers)
  local parts = {}
  for _, q in ipairs(questions) do
    local header = q.header
    local answer = answers[header]
    if answer then
      table.insert(parts, fmt("**%s**: %s", header, answer))
    end
  end
  return table.concat(parts, "\n")
end

---Ask all questions sequentially in the chat buffer, collecting answers
---@param chat CodeCompanion.Chat
---@param questions table Array of question objects
---@param callback fun(answers: table<string, string>) Called with all collected answers
local function ask_all(chat, questions, callback)
  local answers = {}
  local index = 0

  local function next_question()
    index = index + 1
    if index > #questions then
      return callback(answers)
    end

    local question = questions[index]
    question_prompt.ask(chat, {
      question = question,
      index = index,
      total = #questions,
      callback = function(answer)
        answers[question.header] = answer or "No answer provided"
        next_question()
      end,
    })
  end

  next_question()
end

---@class CodeCompanion.Tool.AskQuestions: CodeCompanion.Tools.Tool
return {
  name = "ask_questions",
  cmds = {
    ---@param self CodeCompanion.Tools
    ---@param args { questions: table[] }
    ---@param input { output_cb: fun(msg: { status: string, data: string }) }
    function(self, args, input)
      local questions = args.questions
      if not questions or #questions == 0 then
        return { status = "error", data = "No questions provided" }
      end

      vim.schedule(function()
        ask_all(self.chat, questions, function(answers)
          local response = format_answers(questions, answers)
          if response == "" then
            response = "The user did not provide any answers"
          end
          input.output_cb({ status = "success", data = response })
        end)
      end)
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "ask_questions",
      description = "Ask the user questions to clarify intent, validate assumptions, or choose between implementation approaches. Prefer proposing a sensible default so users can confirm quickly.\n\nOnly use this tool when the user's answer provides information you cannot determine or reasonably assume yourself. This tool is for gathering information, not for reporting status or problems. If a question has an obvious best answer, take that action instead of asking.\n\nIMPORTANT: You may only call this tool ONCE per response. Batch ALL your questions into a single call (up to 4 questions). NEVER call this tool multiple times in the same response.\n\nWhen to use:\n- Clarify ambiguous requirements before proceeding\n- Get user preferences on implementation choices\n- Confirm decisions that meaningfully affect outcome\n\nWhen NOT to use:\n- The answer is determinable from code or context\n- Asking for permission to continue or abort\n- Confirming something you can reasonably decide yourself\n- Reporting a problem (instead, attempt to resolve it)\n- You have already called this tool in the current response",
      parameters = {
        type = "object",
        properties = {
          questions = {
            type = "array",
            description = "Array of 1-4 questions to ask the user",
            items = {
              type = "object",
              properties = {
                header = {
                  type = "string",
                  description = "A short label (max 12 chars) displayed as a header, also used as the unique identifier for the question",
                },
                question = {
                  type = "string",
                  description = "The complete question text to display",
                },
                multiSelect = {
                  type = "boolean",
                  description = "Allow multiple selections",
                },
                options = {
                  type = "array",
                  description = "Options for the user to choose from. If empty or omitted, shows a free text input instead.",
                  items = {
                    type = "object",
                    properties = {
                      label = {
                        type = "string",
                        description = "Option label text",
                      },
                      description = {
                        type = "string",
                        description = "Optional description for the option",
                      },
                      recommended = {
                        type = "boolean",
                        description = "Mark this option as recommended",
                      },
                    },
                    required = { "label" },
                  },
                },
              },
              required = { "header", "question" },
            },
          },
        },
        required = { "questions" },
      },
    },
  },
  handlers = {
    ---@param self CodeCompanion.Tool.AskQuestions
    ---@param meta { tools: CodeCompanion.Tools }
    on_exit = function(self, meta)
      log:trace("[Ask Questions Tool] on_exit handler executed")
    end,
  },
  output = {
    ---@param self CodeCompanion.Tool.AskQuestions
    ---@param meta { tools: CodeCompanion.Tools }
    ---@return string
    prompt = function(self, meta)
      local count = self.args and self.args.questions and #self.args.questions or 0
      return fmt("Ask you %d question%s?", count, count == 1 and "" or "s")
    end,

    ---@param self CodeCompanion.Tool.AskQuestions
    ---@param stdout table
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    success = function(self, stdout, meta)
      local chat = meta.tools.chat
      local llm_output = vim.iter(stdout):flatten():join("\n")
      -- The question prompt already displays the user's answers in the chat buffer
      chat:add_tool_output(self, llm_output, "")
    end,

    ---@param self CodeCompanion.Tool.AskQuestions
    ---@param stderr table
    ---@param meta { tools: CodeCompanion.Tools, cmd: table }
    error = function(self, stderr, meta)
      local chat = meta.tools.chat
      local errors = vim.iter(stderr):flatten():join("\n")
      log:debug("[Ask Questions Tool] Error: %s", stderr)
      chat:add_tool_output(self, errors)
    end,
  },
}
