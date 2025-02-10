---@class vim.treesitter.LanguageTree
---@field parse function

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
---@field opts table The options for the slash command
---@field output fun(selected: table, opts: table): nil The function to call when a selection is made

---@class CodeCompanion.SlashCommandArgs
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config of the slash command
---@field context table The context of the chat buffer from the completion menu
---@field opts table The options for the slash command

---@class CodeCompanion.Variables
---@field vars table The variables from the config

---@class CodeCompanion.Variable
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config for the variable
---@field params string

---@class CodeCompanion.VariableArgs
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config for the variable
---@field params string

---@class CodeCompanion.Cmd
---@field adapter CodeCompanion.Adapter The adapter to use for the chat
---@field context table The context of the buffer that the chat was initiated from
---@field prompts table Any prompts to be sent to the LLM

---@class CodeCompanion.WatcherChange
---@field type "add"|"delete"|"modify" The type of change
---@field start number Starting line number
---@field end_line number Ending line number
---@field lines? string[] Added or deleted lines
---@field old_lines? string[] Original lines (for modify type)
---@field new_lines? string[] New lines (for modify type)

---@class CodeCompanion.Watchers
---@field buffers table<number, CodeCompanion.WatcherState> Map of buffer numbers to their states
---@field augroup integer The autocmd group ID
---@field watch fun(self: CodeCompanion.Watchers, bufnr: number): nil Start watching a buffer
---@field unwatch fun(self: CodeCompanion.Watchers, bufnr: number): nil Stop watching a buffer
---@field get_changes fun(self: CodeCompanion.Watchers, bufnr: number): CodeCompanion.WatcherChange[]|nil Get the latest changes in the buffer

---@class CodeCompanion.WatcherState
---@field content string[] Complete buffer content
---@field changedtick number Last known changedtick
---@field last_sent string[] Last content sent to LLM

---@class CodeCompanion.Subscribers
---@field queue CodeCompanion.Chat.Event[]

---@class CodeCompanion.SubscribersArgs
---@field queue CodeCompanion.Chat.Event[]

---@class CodeCompanion.Chat.Event
---@field callback fun(chat: CodeCompanion.Chat): nil The prompt to send to the LLM
---@field condition fun(chat: CodeCompanion.Chat): boolean The condition to check before sending the prompt
---@field data { name: string, type: string, opts: {auto_submit: boolean } } The data to send to the LLM
---@field id number The unique identifier for the event
---@field reuse fun(chat: CodeCompanion.Chat): boolean Should the current prompt be reused?
---@field order number The order in which the events are executed

---@class CodeCompanion.Chat.Ref
---@field source string The source of the reference e.g. slash_command
---@field id string The unique ID of the reference which links it to a message in the chat buffer and is displayed to the user
---@field opts? table
---@field opts.pinned? boolean Whether this reference is pinned
---@field opts.watched? boolean Whether this reference is being watched for changes
---@field bufnr? number The buffer number if this is a buffer reference

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
---@field output.error? fun(self: CodeCompanion.Tools, cmd: table, error: table|string): any Function to call if the tool is unsuccessful
---@field output.success? fun(self: CodeCompanion.Tools, cmd: table, output: table|string): any Function to call if the tool is successful
---@field request table The request from the LLM to use the Tool

---@class CodeCompanion.Tools
---@field aug number The augroup for the tool
---@field bufnr number The buffer of the chat buffer
---@field chat CodeCompanion.Chat The chat buffer that initiated the tool
---@field extracted table The extracted tools from the LLM's response
---@field messages table The messages in the chat buffer
---@field tool CodeCompanion.Tool The current tool that's being run
---@field agent_config table The agent strategy from the config
---@field tools_ns integer The namespace for the virtual text that appears in the header

---@class CodeCompanion.SlashCommand.Provider
---@field output function The function to call when a selection is made
---@field provider table The path to the provider
---@field title string The title of the provider's window
---@field SlashCommand CodeCompanion.SlashCommand

---@class CodeCompanion.SlashCommand.ProviderArgs
---@field output function The function to call when a selection is made
---@field SlashCommand CodeCompanion.SlashCommand
---@field title string The title of the provider's window

---@class CodeCompanion.Actions.Provider
---@field validate table Validate an item
---@field resolve table Resolve an item into an action
---@field context table Store all arguments in this table

---@class CodeCompanion.Actions.ProvidersArgs Arguments that can be injected into the chat
---@field validate table Validate an item
---@field resolve table Resolve an item into an action
---@field context table The buffer context
