local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local registry = require("codecompanion.interactions.shared.registry")
local utils = require("codecompanion.utils")

local api = vim.api

---@class CodeCompanion.CLI
---@field agent table
---@field aug number
---@field bufnr number
---@field id number
---@field provider CodeCompanion.CLI.Provider
---@field ui CodeCompanion.CLI.UI
local CLI = {}

local _instance = nil

---Keymap callbacks for the CLI buffer
local keymap_callbacks = {
  next_chat = {
    callback = function(cli)
      registry.move(cli.bufnr, 1)
    end,
  },
  previous_chat = {
    callback = function(cli)
      registry.move(cli.bufnr, -1)
    end,
  },
}

---Create or return the singleton CLI instance
---@param args? { agent?: string }
---@return CodeCompanion.CLI|nil
function CLI.get_or_create(args)
  args = args or {}

  -- If an instance already exists and is valid, return it
  if _instance and api.nvim_buf_is_valid(_instance.bufnr) then
    return _instance
  end

  local agent_name = args.agent or config.interactions.cli.agent
  local agent = config.interactions.cli.agents[agent_name]
  if not agent then
    return log:error("CLI agent `%s` not found in config", agent_name or "nil")
  end

  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion CLI] %d", bufnr))

  local id = math.random(10000000)

  local provider = require("codecompanion.interactions.cli.providers").new({
    bufnr = bufnr,
    agent = agent,
  })

  if not provider:start() then
    pcall(api.nvim_buf_delete, bufnr, { force = true })
    return nil
  end

  local ui = require("codecompanion.interactions.cli.ui").new({
    bufnr = bufnr,
  })

  local self = setmetatable({
    agent = agent,
    bufnr = bufnr,
    id = id,
    provider = provider,
    ui = ui,
  }, { __index = CLI }) ---@cast self CodeCompanion.CLI

  if config.interactions.cli.keymaps then
    keymaps
      .new({
        bufnr = bufnr,
        callbacks = keymap_callbacks,
        data = self,
        keymaps = config.interactions.cli.keymaps,
      })
      :set()
  end

  self.aug = api.nvim_create_augroup("codecompanion.cli." .. id, { clear = true })
  api.nvim_create_autocmd("TermClose", {
    group = self.aug,
    buffer = bufnr,
    callback = function()
      vim.schedule(function()
        self:close()
      end)
    end,
  })

  _instance = self

  registry.add(bufnr, {
    name = agent_name,
    description = agent.description or "CLI agent",
    interaction = "cli",
    open = function()
      self.ui:open()
    end,
    hide = function()
      self.ui:hide()
    end,
  })

  log:debug("CLI instance created with agent '%s'", agent_name)
  utils.fire("CLICreated", { bufnr = bufnr })

  return self
end

---Return the singleton instance or nil
---@return CodeCompanion.CLI|nil
function CLI.get_instance()
  if _instance and api.nvim_buf_is_valid(_instance.bufnr) then
    return _instance
  end
  _instance = nil
  return nil
end

---Resolve editor context references in a prompt for CLI output
---@param prompt string
---@param buffer_context CodeCompanion.BufferContext
---@return string
function CLI.resolve_editor_context(prompt, buffer_context)
  local editor_context = require("codecompanion.interactions.chat.editor_context").new()

  -- If the user makes a visiual selection then include it in the prompt
  local triggers = require("codecompanion.triggers")
  local selection_tag = triggers.mappings.editor_context .. "{selection}"
  if buffer_context.is_visual and not prompt:find(vim.pesc(selection_tag), 1, true) then
    prompt = selection_tag .. "\n" .. prompt
  end

  return editor_context:replace_cli(prompt, buffer_context)
end

---Send text to the running CLI agent
---@param text string
---@param opts? { submit: boolean }
---@return nil
function CLI:send(text, opts)
  if not self.provider:is_running() then
    log:warn("CLI agent is not running")
    return
  end

  self.provider:send(text, opts)
  utils.fire("CLISent", { bufnr = self.bufnr, text = text })
end

---Close the CLI instance and clean up
---@return nil
function CLI:close()
  self.provider:stop()

  pcall(api.nvim_del_augroup_by_id, self.aug)

  if api.nvim_buf_is_valid(self.bufnr) then
    pcall(api.nvim_buf_delete, self.bufnr, { force = true })
  end

  registry.remove(self.bufnr)

  log:debug("CLI instance closed")
  utils.fire("CLIClosed", { bufnr = self.bufnr })

  _instance = nil
end

---Check if the CLI is currently visible
---@return boolean
function CLI.is_visible()
  local instance = CLI.get_instance()
  return instance ~= nil and instance.ui:is_visible()
end

---Toggle the CLI terminal buffer
---@param args? { agent?: string }
---@return nil
function CLI.toggle(args)
  args = args or {}

  local instance = CLI.get_instance()

  if not instance then
    instance = CLI.get_or_create({ agent = args.agent })
    if instance then
      instance.ui:open()
    end
    return
  end

  if instance.ui:is_visible_non_curtab() then
    instance.ui:hide()
  end

  if instance.ui:is_visible() then
    instance.ui:hide()
  else
    instance.ui:open()
  end
end

return CLI
