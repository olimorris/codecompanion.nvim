local api = vim.api
local ui = require("codecompanion.utils.ui")

--- Represents a completion item for a slash command in the LSP (Language Server Protocol) context.
---
--- This class extends the lsp.CompletionItem with additional fields specific to slash commands.
---@class CodeCompanion.SlashCommandCompletionItem: lsp.CompletionItem
---@field public slash_command_name? string The name of the command.
---@field public slash_command_args? any The arguments for the command. When the command does not have arguments, this field is nil. and slash_command_not_has_args is true.

--- Represents the response for slash command completion.
---
--- This class encapsulates the completion items for slash commands within
--- the Language Server Protocol, indicating whether the completion is
--- complete and providing a list of available completion items.
---
---@class CodeCompanion.SlashCommandCompletionResponse
---@field public isIncomplete? boolean
---@field public items? CodeCompanion.SlashCommandCompletionItem[]

---@class CodeCompanion.BaseSlashCommand
---
--- This class serves as the base for all slash commands, providing a structure for
--- defining command names, descriptions, execution functions, completion functions,
--- and functions to get fold text representations. It can be extended to create
--- specific commands with additional functionalities.
---@field public name string The name of the command.
---@field public description string A brief description of the command.
---@field public chat CodeCompanion.Chat The chat context in which the command is executed.
local BaseSlashCommand = {}
BaseSlashCommand.__index = BaseSlashCommand

--- Creates a new instance of the BaseSlashCommand.
---
--- This function initializes a new slash command with the given options, which can include
--- a name, description, an execution function, a completion function, and a function to
--- get the fold text representation. If any option is not provided, default values will
--- be used.
---
--- @param opts table A table containing optional parameters:
---    - name: string The name of the command.
---    - description: string A brief description of the command.
---    - execute: function The function to execute when the command is called.
---    - complete: function A function that returns completion items for the command.
---    - get_fold_text: function A function that returns a string for the fold text.
--- @return CodeCompanion.BaseSlashCommand A new instance of CodeCompanion.BaseSlashCommand with the provided options.
function BaseSlashCommand.new(opts)
  local self = setmetatable({}, BaseSlashCommand)
  self:init(opts)
  return self
end

--- Initializes the BaseSlashCommand instance with the provided options.
---
--- This function sets up the command's name, description, execution function,
--- completion function, and function to retrieve fold text. Default values
--- are assigned if any of the options are not provided.
---
--- @param opts table A table containing optional parameters for initialization:
---    - name: string The name of the command.
---    - description: string A brief description of the command.
--- @return nil
function BaseSlashCommand:init(opts)
  opts = opts or {}
  self.name = opts.name
  self.description = opts.description
  self.chat = opts.chat
end

--- Extends the BaseSlashCommand to create a new child command class.
---
--- This function sets up a new table that inherits from BaseSlashCommand, enabling
--- the creation of derived command classes with their own specific behaviors.
--- The new class can be instantiated with its own parameters, which will be
--- initialized using the inherited initialization method.
---
--- @return table A new command class that extends BaseSlashCommand.
function BaseSlashCommand:extend()
  local child = {}
  child.__index = child
  setmetatable(child, {
    __index = self,
    __call = function(cls, ...)
      local instance = setmetatable({}, cls)
      instance:init(...)
      return instance
    end,
  })
  return child
end

--- Executes the slash command with the provided chat context and arguments.
--- This function is meant to be overridden by derived classes to provide
--- specific functionality for each command.
---@param completion_item CodeCompanion.SlashCommandCompletionItem
---@param callback fun(completion_item: CodeCompanion.SlashCommandCompletionItem|nil)
---@diagnostic disable-next-line: unused-local
function BaseSlashCommand:execute(completion_item, callback)
  local chat = self.chat
  local doc = type(completion_item.documentation) == "table" and completion_item.documentation.value
    or string.format("%s", completion_item.documentation)

  local start_line = api.nvim_buf_line_count(chat.bufnr)
  chat:append({ content = doc })
  local end_line = api.nvim_buf_line_count(chat.bufnr)

  ---@diagnostic disable-next-line: deprecated
  api.nvim_buf_set_option(chat.bufnr, "foldmethod", "manual")
  api.nvim_buf_call(chat.bufnr, function()
    vim.fn.setpos(".", { chat.bufnr, start_line, 0, 0 })
    vim.cmd("normal! zf" .. end_line .. "G")
  end)
  ui.buf_scroll_to_end(chat.bufnr)

  return callback()
end

--- Completes the command based on the provided input.
--- This function is meant to be overridden by derived classes to provide
--- specific completion functionality for each command.
--- @param params cmp.SourceCompletionApiParams The completion parameters.
--- @param callback fun(response: CodeCompanion.SlashCommandCompletionResponse|nil) The callback function to return the completion response.
--- @return nil
---@diagnostic disable-next-line: unused-local
function BaseSlashCommand:complete(params, callback) end

---Resolve completion item (optional). This is called right before the completion is about to be displayed.
---Useful for setting the text shown in the documentation window (`completion_item.documentation`).
---@param completion_item CodeCompanion.SlashCommandCompletionItem
---@param callback fun(completion_item: CodeCompanion.SlashCommandCompletionItem|nil)
function BaseSlashCommand:resolve(completion_item, callback)
  callback(completion_item)
end

---@class CodeCompanion.SlashCommandManager
---
--- This class manages a collection of slash commands, providing functionalities
--- to register new commands, execute commands, and provide command completions.
--- It serves as a central hub for handling all slash commands within the system.
---@field public commands CodeCompanion.BaseSlashCommand[] A table mapping command names to their respective BaseSlashCommand instances.
---@field public chat CodeCompanion.Chat The chat context in which the commands are executed.
local SlashCommandManager = {}

---@param chat CodeCompanion.Chat The chat context in which the command is executed.
function SlashCommandManager.new(chat)
  local self = setmetatable({}, { __index = SlashCommandManager })
  self.commands = {}
  self.chat = chat
  return self
end

--- Registers a new slash command in the command manager.
---
--- This function maps the command's name to its corresponding
--- BaseSlashCommand instance, allowing for later execution and
--- completion functionality.
---
--- @param command CodeCompanion.BaseSlashCommand The command instance to register.
function SlashCommandManager:register(command)
  if not command or not command.name then
    return
  end

  self.commands[command.name] = command
end

--- Retrieves a registered slash command by its name.
---
--- This function checks if a command exists in the command manager's
--- collection. If found, it returns the corresponding
--- BaseSlashCommand instance.
---
--- @param command string The name of the command to retrieve.
--- @return CodeCompanion.BaseSlashCommand|nil The command instance if found, or nil if not.
function SlashCommandManager:get(command)
  if self.commands[command] then
    return self.commands[command]
  end
end

return {
  BaseSlashCommand = BaseSlashCommand,
  SlashCommandManager = SlashCommandManager,
}
