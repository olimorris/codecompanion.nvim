local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local fmt = string.format

local CONSTANTS = {
  -- Ref: https://www.reddit.com/r/ClaudeAI/comments/1jr52qj/here_is_claude_codes_compact_prompt/
  PROMPT = [[Your task is to create a detailed summary of the conversation so far, paying close attention to the user's explicit requests and your previous actions.
This summary should be thorough in capturing technical details, code patterns, and architectural decisions that would be essential for continuing development work without losing context.

Before providing your final summary, you must first perform an analysis of the conversation, outputting a summary.

The "summary" should be a Markdown-formatted summary. It must include the following sections, each with a Markdown header:

- "Primary Request and Intent": Capture all of the user's explicit requests and intents in detail.
- "Key Technical Concepts": List all important technical concepts, technologies, and frameworks discussed.
- "Files and Code Sections": Enumerate specific files and code sections examined, modified, or created. Pay special attention to the most recent messages and include full code snippets where applicable and include a summary of why this file read or edit is important.
- "Problem Solving": Document problems solved and any ongoing troubleshooting efforts.
- "Pending Tasks": Outline any pending tasks that you have explicitly been asked to work on.
- "Current Work": Describe in detail precisely what was being worked on immediately before this summary request, paying special attention to the most recent messages from both user and assistant. Include file names and code snippets where applicable.
- "Optional Next Step": List the next step that you will take that is related to the most recent work you were doing. IMPORTANT: ensure that this step is DIRECTLY in line with the user's explicit requests, and the task you were working on immediately before this summary request. If your last task was concluded, then only list next steps if they are explicitly in line with the users request. Do not start on tangential requests without confirming with the user first.
- "Supporting Quotes": If there is a next step, include direct quotes from the most recent conversation showing exactly what task you were working on and where you left off. This should be verbatim to ensure there's no drift in task interpretation.

Here's an example of how a summary might be structured:

---
### Primary Request and Intent

[Detailed description]

### Key Technical Concepts

- [Concept 1]
- [Concept 2]

### Files and Code Sections

- **[File Name 1]**
- [Summary of why this file is important]
- [Summary of the changes made to this file, if any]

````[language]
[Important Code Snippet]
````

### Problem Solving

[Description of solved problems and ongoing troubleshooting]

### Pending Tasks

- [Task 1]
- [Task 2]

### Current Work

[Precise description of current work]

### Optional Next Step

[Optional Next step to take]

### Supporting Quotes

> [Verbatim quotes from the conversation]
---

Please provide your summary based on the conversation so far, following this structure and ensuring precision and thoroughness in your response.

Include the markdown only, without any additional commentary or explanation and no markdown formatting. If you're referencing any code in your summary, ensure that is wrapped in FOUR backticks followed by the appropriate language identifier for syntax highlighting. For example:

````python
def example_function():
    pass
````

The conversation and corresponding messages to summarize, is as follows:

<conversation>%s</conversation>]],
}

---@class CodeCompanion.SlashCommand.Compact: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---Create the conversation string from messages
---@param messages CodeCompanion.Chat.Messages
---@return string
function SlashCommand:create_conversation(messages)
  --Rules:
  --1. We only care about user and assistant messages
  local conversation = ""

  for _, message in ipairs(messages or {}) do
    if message.role == "user" or message.role == "assistant" then
      conversation = conversation .. fmt('<message role="%s">%s</message>', message.role, message.content)
    end
  end

  return conversation
end

---Compact the messages, removing user and llm roles
---@return nil
function SlashCommand:compact_messages()
  --Rules:
  --1. Keep ALL system messages even if they come from tools
  --2. Remove ALL llm messages
  --3. Keep SOME user messages - If it has a "variable", "rules" or "file" tag
  local ok_tags = { "editor_context", "rules", "file" }

  local messages = vim.iter(self.Chat.messages):filter(function(message)
    if message.role == config.constants.SYSTEM_ROLE then
      return true
    elseif message.role == config.constants.LLM_ROLE then
      return false
    elseif message.role == config.constants.USER_ROLE then
      if message._meta and message._meta.tag then
        if vim.tbl_contains(ok_tags, message._meta.tag) then
          return true
        else
          return false
        end
      end
    end

    return false
  end)

  self.Chat.messages = messages:totable()
end

---Execute the slash command
---@param SlashCommands CodeCompanion.SlashCommands
---@return nil
function SlashCommand:execute(SlashCommands)
  return vim.ui.select({ "Yes", "No" }, {
    kind = "codecompanion.nvim",
    prompt = "Generate a compact summary of the conversation so far?",
  }, function(selected)
    if not selected or selected == "No" then
      return
    end

    local request = require("codecompanion.interactions.background")
      .new({
        adapter = self.Chat.adapter,
      })
      :ask({
        {
          role = "user",
          content = fmt(CONSTANTS.PROMPT, self:create_conversation(self.Chat.messages)),
        },
      }, {
        method = "async",
        on_done = function(result)
          if result then
            local content = result.output and result.output.content

            -- I don't care about the analysis field. I include that in the
            -- prompt to guide the model's thinking process.
            self.Chat:add_buf_message({
              role = config.constants.USER_ROLE,
              content = fmt("Below is a summary of a conversation we've previously had:\n\n%s\n\n", content),
            })
            self:compact_messages()

            return log:debug("[Compact] Compacted the chat history")
          end
          log:debug("[Compact] No result from compacting the conversation")
        end,
        on_error = function(err)
          return log:error("[Compact] Error compacting the conversation: %s", err)
        end,
      })
  end)
end

return SlashCommand
