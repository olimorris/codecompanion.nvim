local buf_utils = require("codecompanion.utils.buffers")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---Resolve a path to the correct module
---@param path string The module or file path
---@return table|nil
local function resolve(path)
  local ok, slash_command = pcall(require, "codecompanion." .. path)
  if ok then
    log:debug("Calling slash command: %s", path)
    return slash_command
  end

  -- Try loading from the user's config using a module path
  ok, slash_command = pcall(require, path)
  if ok then
    log:debug("Calling slash command using a module path: %s", path)
    return slash_command
  end

  -- Try loading from the user's config using a file path
  local err
  slash_command, err = loadfile(vim.fs.normalize(path))
  if err then
    return log:error("Could not load the slash command: %s", path)
  end

  if slash_command then
    log:debug("Calling slash command from a file path: %s", path)
    return slash_command()
  end
end

---@class CodeCompanion.SlashCommands
local SlashCommands = {}

---@class CodeCompanion.SlashCommands
function SlashCommands.new()
  return setmetatable({}, { __index = SlashCommands })
end

---Set the provider to use for the Slash Command
---@param SlashCommand CodeCompanion.SlashCommand
---@param providers table
---@return function
function SlashCommands:set_provider(SlashCommand, providers)
  if SlashCommand.config.opts and SlashCommand.config.opts.provider then
    if not providers[SlashCommand.config.opts.provider] then
      return log:error("Provider for the slash command could not be found: %s", SlashCommand.config.opts.provider)
    end
    return providers[SlashCommand.config.opts.provider](SlashCommand) --[[@type function]]
  end
  return providers["default"] --[[@type function]]
end

---Execute the selected slash command
---@param item table The selected item from the completion menu
---@param chat CodeCompanion.Chat
---@return nil
function SlashCommands:execute(item, chat)
  local label = item.label:sub(1)
  log:debug("Executing slash command: %s", label)

  -- If the user has provided a callback function, use that
  if type(item.config.callback) == "function" then
    return item.config.callback(chat)
  end

  local resolved = resolve(item.config.path)
  if not resolved then
    return log:error("Slash command not found: %s", label)
  end

  if resolved.enabled then
    local enabled, err = resolved.enabled(chat)
    if enabled == false then
      return log:warn(err)
    end
  end

  return resolved
    .new({
      Chat = chat,
      config = item.config,
      context = item.context,
    })
    :execute(self)
end

---Function for external objects to add context via Slash Commands
---@param chat CodeCompanion.Chat
---@param slash_command string
---@param opts { path: string, url?: string, description: string, [any]: any }
---@return nil
function SlashCommands.context(chat, slash_command, opts)
  local slash_commands = {
    buffer = require("codecompanion.interactions.chat.slash_commands.builtin.buffer").new({
      Chat = chat,
      config = config.interactions.chat.slash_commands["buffer"],
    }),
    file = require("codecompanion.interactions.chat.slash_commands.builtin.file").new({
      Chat = chat,
    }),
    symbols = require("codecompanion.interactions.chat.slash_commands.builtin.symbols").new({
      Chat = chat,
    }),
    url = require("codecompanion.interactions.chat.slash_commands.builtin.fetch").new({
      Chat = chat,
      config = config.interactions.chat.slash_commands["fetch"],
    }),
  }

  -- Check if the file is already open as a buffer
  if slash_command == "file" then
    local buffer = {}
    for _, buf in ipairs(buf_utils.get_open()) do
      if buf.path == opts.path then
        buffer = {
          bufnr = buf.bufnr,
          name = buf.path,
          path = buf.path,
        }
        break
      end
    end
    if not vim.tbl_isempty(buffer) then
      return slash_commands["buffer"]:output(buffer, { description = opts.description, silent = true })
    end
  end

  if slash_command == "file" or slash_command == "symbols" then
    return slash_commands[slash_command]:output({ description = opts.description, path = opts.path }, { silent = true })
  end

  if slash_command == "url" then
    -- NOTE: To conform to the <path, description> interface, we need to pass all
    -- other options via the opts table. Then, of course, we need to strip the
    -- double opts out of the opts table. Hacky, for sure.
    opts.silent = true
    opts.url = opts.url or opts.path
    opts.description = opts.description
    opts.auto_restore_cache = opts.opts and opts.opts.auto_restore_cache
    opts.ignore_cache = opts.opts and opts.opts.ignore_cache

    return slash_commands[slash_command]:output(opts.url, opts)
  end
end

return SlashCommands
