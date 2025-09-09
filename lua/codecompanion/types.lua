---@meta Agent Client Protocol

---@class ACP.promptCapabilities
---@field audio boolean
---@field embeddedContext boolean
---@field image boolean

---@class ACP.agentCapabilities
---@field loadSession boolean
---@field promptCapabilities ACP.promptCapabilities

---@class ACP.AuthMethod
---@field id string
---@field name string
---@field description? string|nil

---@alias ACP.authMethods ACP.AuthMethod[]

---@meta Tree-sitter

---@class vim.treesitter.LanguageTree
---@field parse function

---@class TSNode
---@field start_pos function
---@field end_pos function
---@field type function
---@field parent function

---@class TSQuery

---@meta CodeCompanion

---@alias CodeCompanion.Chat.Messages CodeCompanion.Chat.Message[]

---@class CodeCompanion.Chat.Message
---@field id number Unique identifier for the message (generated via hash)
---@field role string Role of the author (e.g. "user", "llm", "system", "tool")
---@field content string The raw Markdown/text content of the message (optional for tool-only entries)
---@field cycle number The chat turn cycle when this message was added
---@field opts? table Optional metadata used by the UI and processing
---@field opts.visible? boolean Whether the message should be shown in the chat UI
---@field opts.tag? string A tag to identify special messages (e.g. "system_prompt_from_config", "tool")
---@field opts.context_id? string Link to a context item (used for pinned/context messages)
---@field opts.pinned? boolean Whether the context message is pinned
---@field opts.index? number If set, the message was inserted at this index
---@field opts.watched? boolean Whether the context is being watched for changes
---@field _meta table Internal metadata (e.g. { sent = true })
---@field reasoning? CodeCompanion.Chat.Reasoning Optional reasoning object returned by some adapters
---@field tool_calls? CodeCompanion.Chat.ToolCall[] Array of tool call descriptors attached to this message
---@field tool_call_id? string Optional single tool call id that this message represents (links tool output -> call)
---@field type? string Optional message type used by the UI (e.g. "llm_message", "tool_message", "reasoning_message")
---@field _raw? any Any adapter-specific raw payload stored with the message
---@field created_at? number Unix timestamp (optional, helpful for sorting/logging)
---@field tokens? number Optional token count associated with this message

---@class CodeCompanion.Chat.ToolFunctionCall
---@field name string Name of the function/tool (e.g. "cmd_runner", "grep_search")
---@field arguments string|table Raw JSON string or parsed table of arguments

---@class CodeCompanion.Chat.ToolCall
---@field id string Unique tool call identifier (e.g. "call_8Aoq8...")
---@field type string Typically "function" (adapter/tool-specific)
---@field _index? number Position index when returned by adapters
---@field ["function"]? CodeCompanion.Chat.ToolFunctionCall Function descriptor (adapter key name is "function")
---@field result? any Optional execution result or intermediate payload

---@class CodeCompanion.Chat.Reasoning
---@field content string The LLM's chain-of-thought / internal reasoning (often markdown)
---@field meta? table Optional structured reasoning metadata

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
---@field target string The buffer that's being targeted by the variable
---@field params string Any additional parameters for the variable

---@class CodeCompanion.VariableArgs
---@field Chat CodeCompanion.Chat The chat buffer
---@field config table The config for the variable
---@field target string The buffer that's being targeted by the variable
---@field params string Any additional parameters for the variable

---@class CodeCompanion.Watchers
---@field buffers table<number, CodeCompanion.WatcherState> Map of buffer numbers to their states
---@field augroup integer The autocmd group ID
---@field watch fun(self: CodeCompanion.Watchers, bufnr: number): nil Start watching a buffer
---@field unwatch fun(self: CodeCompanion.Watchers, bufnr: number): nil Stop watching a buffer
---@field get_changes fun(self: CodeCompanion.Watchers, bufnr: number): boolean, table

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

---@class CodeCompanion.Chat.ContextItem
---@field bufnr? number The buffer number if this is buffer context
---@field id string The unique ID of the context which links it to a message in the chat buffer and is displayed to the user
---@field source string The source of the context e.g. slash_command
---@field opts? table
---@field opts.pinned? boolean Whether this context item is pinned
---@field opts.watched? boolean Whether this context item is being watched for changes
---@field opts.visible? boolean Whether this context item should be shown in the chat UI

---@class CodeCompanion.Tools.Tool
---@field name string The name of the tool
---@field cmds table The commands to execute
---@field function_call table The function call from the LLM
---@field schema table The schema that the LLM must use in its response to execute a tool
---@field system_prompt string | fun(schema: table): string The system prompt to the LLM explaining the tool and the schema
---@field opts? table The options for the tool
---@field env? fun(schema: table): table|nil Any environment variables that can be used in the *_cmd fields. Receives the parsed schema from the LLM
---@field handlers table Functions which handle the execution of a tool
---@field handlers.setup? fun(self: CodeCompanion.Tools.Tool, tools: CodeCompanion.Tools): any Function used to setup the tool. Called before any commands
---@field handlers.prompt_condition? fun(self: CodeCompanion.Tools.Tool, tools: CodeCompanion.Tools, config: table): boolean Function to determine whether to show the promp to the user or not
---@field handlers.on_exit? fun(self: CodeCompanion.Tools.Tool, tools: CodeCompanion.Tools): any Function to call at the end of a group of commands or functions
---@field output? table Functions which handle the output after every execution of a tool
---@field output.prompt fun(self: CodeCompanion.Tools.Tool, tools: CodeCompanion.Tools): string The message which is shared with the user when asking for their approval
---@field output.rejected? fun(self: CodeCompanion.Tools.Tool, tools: CodeCompanion.Tools, cmd: table): any Function to call if the user rejects running a command
---@field output.error? fun(self: CodeCompanion.Tools.Tool, tools: CodeCompanion.Tools, cmd: table, stderr: table, stdout?: table): any The function to call if an error occurs
---@field output.success? fun(self: CodeCompanion.Tools.Tool, tools: CodeCompanion.Tools, cmd: table, stdout: table): any Function to call if the tool is successful
---@field output.cancelled? fun(self: CodeCompanion.Tools.Tool, tools: CodeCompanion.Tools, cmd: table): any Function to call if the tool is cancelled
---@field args table The arguments sent over by the LLM when making the request
---@field tool table The tool configuration from the config file

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
