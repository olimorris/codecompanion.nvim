---@class TSNode
---@field start_pos function
---@field end_pos function
---@field type function
---@field parent function

---@class TSQuery

---@meta CodeCompanion

---@class CodeCompanion.SlashCommand
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config of the slash command
---@field context table The context of the chat buffer from the completion menu

---@class CodeCompanion.SlashCommandArgs
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config of the slash command
---@field context table The context of the chat buffer from the completion menu

---@class CodeCompanion.Chat
---@field opts CodeCompanion.ChatArgs Store all arguments in this table
---@field adapter CodeCompanion.Adapter The adapter to use for the chat
---@field aug number The ID for the autocmd group
---@field bufnr integer The buffer number of the chat
---@field context table The context of the buffer that the chat was initiated from
---@field current_request table|nil The current request being executed
---@field current_tool table The current tool being executed
---@field cycle number The amount of times the chat has been sent to the LLM
---@field header_ns integer The namespace for the virtual text that appears in the header
---@field id integer The unique identifier for the chat
---@field intro_message? boolean Whether the welcome message has been shown
---@field messages? table The messages in the chat buffer
---@field References CodeCompanion.Chat.References
---@field refs? table<CodeCompanion.Chat.Ref> References which are sent to the LLM e.g. buffers, slash command output
---@field settings? table The settings that are used in the adapter of the chat buffer
---@field subscribers table The subscribers to the chat buffer
---@field tokens? nil|number The number of tokens in the chat
---@field tools? CodeCompanion.Tools The tools available to the user
---@field tools_in_use? nil|table The tools that are currently being used in the chat
---@field variables? CodeCompanion.Variables The variables available to the user

---@class CodeCompanion.ChatArgs Arguments that can be injected into the chat
---@field adapter? CodeCompanion.Adapter The adapter used in this chat buffer
---@field auto_submit? boolean Automatically submit the chat when the chat buffer is created
---@field context? table Context of the buffer that the chat was initiated from
---@field last_role? string The role of the last response in the chat buffer
---@field messages? table The messages to display in the chat buffer
---@field settings? table The settings that are used in the adapter of the chat buffer
---@field status? string The status of any running jobs in the chat buffe
---@field stop_context_insertion? boolean Stop any visual selection from being automatically inserted into the chat buffer
---@field tokens? table Total tokens spent in the chat buffer so far

---@class CodeCompanion.Chat.Ref
---@field source string The source of the reference e.g. slash_command
---@field name string The name of the source e.g. buffer
---@field id string The unique ID of the reference which links it to a message in the chat buffer and is displayed to the user
---@field opts? table
