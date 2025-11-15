local chat_helpers = require("codecompanion.strategies.chat.helpers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  -- Ref: https://www.reddit.com/r/ClaudeAI/comments/1jr52qj/here_is_claude_codes_compact_prompt/
  PROMPT = [[Your task is to create a detailed summary of the conversation so far, paying close attention to the user's explicit requests and your previous actions.
This summary should be thorough in capturing technical details, code patterns, and architectural decisions that would be essential for continuing development work without losing context.

Before providing your final summary, you must first perform an analysis of the conversation. Your entire output must be a single JSON object.

The JSON object should have two top-level keys: "analysis" and "summary".

In the "analysis" field, you should place your thought process. In this process:
1. Chronologically analyze each message and section of the conversation. For each section thoroughly identify:
   - The user's explicit requests and intents
   - Your approach to addressing the user's requests
   - Key decisions, technical concepts and code patterns
   - Specific details like file names, full code snippets, function signatures, file edits, etc
2. Double-check for technical accuracy and completeness, addressing each required element thoroughly.

The "summary" field should be a single string containing a Markdown-formatted summary. The summary must include the following sections, each with a Markdown header:

- "Primary Request and Intent": Capture all of the user's explicit requests and intents in detail.
- "Key Technical Concepts": List all important technical concepts, technologies, and frameworks discussed.
- "Files and Code Sections": Enumerate specific files and code sections examined, modified, or created. Pay special attention to the most recent messages and include full code snippets where applicable and include a summary of why this file read or edit is important.
- "Problem Solving": Document problems solved and any ongoing troubleshooting efforts.
- "Pending Tasks": Outline any pending tasks that you have explicitly been asked to work on.
- "Current Work": Describe in detail precisely what was being worked on immediately before this summary request, paying special attention to the most recent messages from both user and assistant. Include file names and code snippets where applicable.
- "Optional Next Step": List the next step that you will take that is related to the most recent work you were doing. IMPORTANT: ensure that this step is DIRECTLY in line with the user's explicit requests, and the task you were working on immediately before this summary request. If your last task was concluded, then only list next steps if they are explicitly in line with the users request. Do not start on tangential requests without confirming with the user first.
- "Supporting Quotes": If there is a next step, include direct quotes from the most recent conversation showing exactly what task you were working on and where you left off. This should be verbatim to ensure there's no drift in task interpretation.

Here's an example of how your JSON output should be structured:

```json
{
  "analysis": "[Your thought process, ensuring all points are covered thoroughly and accurately]",
  "summary": "### Primary Request and Intent\n[Detailed description]\n\n### Key Technical Concepts\n- [Concept 1]\n- [Concept 2]\n\n### Files and Code Sections\n- **[File Name 1]**\n  - [Summary of why this file is important]\n  - [Summary of the changes made to this file, if any]\n  - ```[language]\n[Important Code Snippet]\n```\n\n### Problem Solving\n[Description of solved problems and ongoing troubleshooting]\n\n### Pending Tasks\n- [Task 1]\n- [Task 2]\n\n### Current Work\n[Precise description of current work]\n\n### Optional Next Step\n[Optional Next step to take]\n\n### Supporting Quotes\n> [Verbatim quotes from the conversation]"
}
```

Please provide your summary based on the conversation so far, following this JSON structure and ensuring precision and thoroughness in your response.
Include the JSON object only, without any additional commentary or explanation and no markdown formatting.]],
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

---Execute the slash command
---@param SlashCommands CodeCompanion.SlashCommands
---@return nil
function SlashCommand:execute(SlashCommands) end

---Output from the slash command in the chat buffer
---@param selected table The selected item from the provider { relative_path = string, path = string }
---@param opts? table
---@return nil
function SlashCommand:output(selected, opts) end

return SlashCommand
