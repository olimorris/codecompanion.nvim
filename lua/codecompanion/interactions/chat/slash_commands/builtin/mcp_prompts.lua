local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local mcp = require("codecompanion.mcp")
local utils = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  PROMPT = "Select an MCP prompt",
}

---@param server_prompt { server: string, prompt: MCP.Prompt }
---@return string
local function format_item(server_prompt)
  local label = fmt("%s: %s", server_prompt.server, server_prompt.prompt.title or server_prompt.prompt.name)
  if server_prompt.prompt.description then
    return fmt("%s - %s", label, server_prompt.prompt.description)
  end
  return label
end

---@param argument MCP.PromptArgument
---@return string
local function format_argument(argument)
  local label = argument.required and fmt("%s (required)", argument.name) or argument.name
  if argument.description then
    return fmt("%s: %s ", label, argument.description)
  end
  return label .. ": "
end

---Ask for each of the prompt's arguments in turn, stopping if the user cancels
---@param prompt MCP.Prompt
---@param opts { callback: fun(arguments: table<string, string>) }
local function ask_for_arguments(prompt, opts)
  -- Without this, a prompt with no arguments sends `[]` and servers expecting an object reject it
  local arguments = vim.empty_dict()
  local prompt_arguments = prompt.arguments or {}

  local function ask(index)
    local argument = prompt_arguments[index]
    if not argument then
      return opts.callback(arguments)
    end

    vim.ui.input({ prompt = format_argument(argument) }, function(value)
      if value == nil then
        return
      end
      if value == "" and argument.required then
        return utils.notify(fmt("MCP prompt argument `%s` is required", argument.name), vim.log.levels.WARN)
      end
      if value ~= "" then
        arguments[argument.name] = value
      end
      ask(index + 1)
    end)
  end

  ask(1)
end

---Join the text from the prompt's user messages, skipping everything else
---@param result MCP.GetPromptResult
---@return string
local function get_user_text(result)
  local texts = {}
  for _, message in ipairs(result.messages) do
    if message.role == "user" and message.content.type == "text" then
      table.insert(texts, message.content.text)
    else
      log:debug("[MCP Prompts] Skipping a `%s` message with `%s` content", message.role, message.content.type)
    end
  end
  return table.concat(texts, "\n\n")
end

---@class CodeCompanion.SlashCommand.MCPPrompts: CodeCompanion.SlashCommand
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

---@return boolean, string?
function SlashCommand.enabled()
  if vim.tbl_isempty(config.mcp.servers or {}) then
    return false, "[MCP] No servers found in your configuration"
  end
  return true
end

function SlashCommand:execute()
  mcp.get_prompts({
    callback = function(prompts)
      if #prompts == 0 then
        return utils.notify("No prompts available from running MCP servers - start a server with `/mcp`")
      end

      vim.ui.select(prompts, {
        kind = "codecompanion.nvim",
        prompt = CONSTANTS.PROMPT,
        format_item = format_item,
      }, function(selected)
        if not selected then
          return
        end
        ask_for_arguments(selected.prompt, {
          callback = function(arguments)
            self:output(selected, { arguments = arguments })
          end,
        })
      end)
    end,
  })
end

---Get the prompt from the server and add its text to the chat buffer
---@param selected { server: string, prompt: MCP.Prompt }
---@param opts { arguments: table<string, string> }
function SlashCommand:output(selected, opts)
  mcp.get_prompt({
    server = selected.server,
    name = selected.prompt.name,
    arguments = opts.arguments,
    callback = function(ok, result)
      if not ok then
        return utils.notify(result --[[@as string]], vim.log.levels.ERROR)
      end
      if not vim.api.nvim_buf_is_valid(self.Chat.bufnr) then
        return
      end
      if self.Chat.current_request then
        return utils.notify(
          fmt("MCP prompt `%s` was not added as the chat is responding", selected.prompt.name),
          vim.log.levels.WARN
        )
      end

      local text = get_user_text(result --[[@as MCP.GetPromptResult]])
      if text == "" then
        return utils.notify(fmt("MCP prompt `%s` has no text to add", selected.prompt.name), vim.log.levels.WARN)
      end

      self.Chat:add_buf_message({ role = config.constants.USER_ROLE, content = text })
    end,
  })
end

return SlashCommand
