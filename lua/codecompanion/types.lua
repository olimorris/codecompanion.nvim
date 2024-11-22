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

---@class CodeCompanion.Variables
---@field vars table The variables from the config

---@class CodeCompanion.Variable
---@field chat CodeCompanion.Chat The chat buffer
---@field params table The context of the chat buffer from the completion menu

---@class CodeCompanion.VariableArgs
---@field chat CodeCompanion.Chat The chat buffer
---@field params table The context of the chat buffer from the completion menu

---@class CodeCompanion.Cmd
---@field adapter CodeCompanion.Adapter The adapter to use for the chat
---@field context table The context of the buffer that the chat was initiated from
---@field prompts table Any prompts to be sent to the LLM

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
---@field ui CodeCompanion.Chat.UI The UI of the chat buffer
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

---@class CodeCompanion.Chat.UI
---@field adapter CodeCompanion.Adapter
---@field aug number
---@field bufnr number
---@field header_ns number
---@field id number
---@field roles table
---@field winnr number
---@field settings table
---@field tokens number

---@class CodeCompanion.Chat.UIArgs
---@field adapter CodeCompanion.Adapter
---@field bufnr number
---@field id number
---@field roles table
---@field winnr number
---@field settings table
---@field tokens number

---@class CodeCompanion.Tool
---@field name string The name of the tool
---@field cmds table The commands to execute
---@field schema table The schema that the LLM must use in its response to execute a tool
---@field system_prompt fun(schema: table): string The system prompt to the LLM explaining the tool and the schema
---@field opts? table The options for the tool
---@field env? fun(schema: table): table|nil Any environment variables that can be used in the *_cmd fields. Receives the parsed schema from the LLM
---@field handlers table Functions which can be called during the execution of the tool
---@field handlers.setup? fun(self: CodeCompanion.Tools): any Function used to setup the tool. Called before any commands
---@field handlers.approved? fun(self: CodeCompanion.Tools): boolean Function to call if an approval is needed before running a command
---@field handlers.on_exit? fun(self: CodeCompanion.Tools): any Function to call at the end of all of the commands
---@field output? table Functions which can be called after the command finishes
---@field output.rejected? fun(self: CodeCompanion.Tools, cmd: table): any Function to call if the user rejects running a command
---@field output.error? fun(self: CodeCompanion.Tools, cmd: table, error: table|string): any Function to call if the tool is unsuccesful
---@field output.success? fun(self: CodeCompanion.Tools, cmd: table, output: table|string): any Function to call if the tool is successful
---@field request table The request from the LLM to use the Tool

---@class CodeCompanion.Tools
---@field aug number The augroup for the tool
---@field bufnr number The buffer of the chat buffer
---@field chat CodeCompanion.Chat The chat buffer that initiated the tool
---@field messages table The messages in the chat buffer
---@field tool CodeCompanion.Tool The current tool that's being run
---@field agent_config table The agent strategy from the config
---@field tools_ns integer The namespace for the virtual text that appears in the header
