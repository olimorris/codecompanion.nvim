-- File watching logic inspired and adapted from sidekick.nvim
-- https://github.com/folke/sidekick.nvim

local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local registry = require("codecompanion.interactions.shared.registry")
local utils = require("codecompanion.utils")

local api = vim.api

local uv = vim.uv or vim.loop

---@type table
_G.codecompanion_cli_metadata = {}

---@class CodeCompanion.CLI
---@field agent table
---@field agent_name string
---@field aug number
---@field bufnr number
---@field id number
---@field provider CodeCompanion.CLI.Provider
---@field ui CodeCompanion.CLI.UI
---@field watcher uv.uv_fs_event_t|nil
---@field watch_timer uv.uv_timer_t|nil
local CLI = {}

local clis = {} ---@type table<number, CodeCompanion.CLI>
local last_cli = nil ---@type CodeCompanion.CLI|nil

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

---Create a new CLI instance
---@param args? { agent?: string }
---@return CodeCompanion.CLI|nil
function CLI.create(args)
  args = args or {}

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
    agent_name = agent_name,
    bufnr = bufnr,
    id = id,
    provider = provider,
    ui = ui,
  }, { __index = CLI }) ---@cast self CodeCompanion.CLI

  keymaps
    .new({
      bufnr = bufnr,
      callbacks = keymap_callbacks,
      data = self,
      keymaps = config.interactions.cli.keymaps,
    })
    :set()

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

  if config.interactions.cli.opts.auto_insert then
    api.nvim_create_autocmd("BufEnter", {
      group = self.aug,
      buffer = bufnr,
      callback = function()
        vim.cmd.startinsert()
      end,
    })
    api.nvim_create_autocmd("BufLeave", {
      group = self.aug,
      buffer = bufnr,
      callback = function()
        vim.cmd.stopinsert()
      end,
    })
  end

  if config.interactions.cli.opts.reload then
    self:_start_watcher()
  end

  clis[bufnr] = self
  last_cli = self

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

  self:update_metadata()

  log:debug("CLI instance created with agent '%s'", agent_name)
  utils.fire("CLICreated", { bufnr = bufnr })

  return self
end

---Return the last-used CLI instance, or nil if none exist
---@return CodeCompanion.CLI|nil
function CLI.last_cli()
  if last_cli and api.nvim_buf_is_valid(last_cli.bufnr) then
    return last_cli
  end
  last_cli = nil
  return nil
end

---Find an existing CLI instance by agent name
---@param agent_name string
---@return CodeCompanion.CLI|nil
function CLI.find_by_agent(agent_name)
  for _, instance in pairs(clis) do
    if instance.agent_name == agent_name and api.nvim_buf_is_valid(instance.bufnr) then
      return instance
    end
  end
  return nil
end

---Resolve editor context references in a prompt for CLI output
---@param prompt string
---@param buffer_context CodeCompanion.BufferContext
---@return string
function CLI.resolve_editor_context(prompt, buffer_context)
  local editor_context = require("codecompanion.interactions.shared.editor_context").new("cli")

  -- If the user makes a visiual selection then include it in the prompt
  local triggers = require("codecompanion.triggers")
  local selection_tag = triggers.mappings.editor_context .. "{selection}"
  if buffer_context.is_visual and not prompt:find(vim.pesc(selection_tag), 1, true) then
    prompt = selection_tag .. "\n" .. prompt
  end

  return editor_context:replace_cli(prompt, buffer_context)
end

---Update the global metadata table for statusline integrations
---@return nil
function CLI:update_metadata()
  _G.codecompanion_cli_metadata[self.bufnr] = {
    agent = self.agent_name,
    description = self.agent.description,
    id = self.id,
    running = self.provider:is_running(),
  }
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
  self:_stop_watcher()
  self.provider:stop()

  pcall(api.nvim_del_augroup_by_id, self.aug)

  if api.nvim_buf_is_valid(self.bufnr) then
    pcall(api.nvim_buf_delete, self.bufnr, { force = true })
  end

  registry.remove(self.bufnr)
  _G.codecompanion_cli_metadata[self.bufnr] = nil

  clis[self.bufnr] = nil
  if last_cli and last_cli.bufnr == self.bufnr then
    last_cli = nil
  end

  log:debug("CLI instance closed")
  utils.fire("CLIClosed", { bufnr = self.bufnr })
end

--=============================================================================
-- Watcher for auto-reloading buffers on file changes
-- =============================================================================

---Start watching the cwd for file changes and reload buffers
---@return nil
function CLI:_start_watcher()
  local cwd = vim.fn.getcwd()

  self.watcher = uv.new_fs_event()
  if not self.watcher then
    return log:warn("Could not create file watcher")
  end

  self.watch_timer = uv.new_timer()

  self.watcher:start(cwd, { recursive = true }, function()
    -- Debounce: restart a 100ms timer on each event
    if self.watch_timer then
      self.watch_timer:stop()
      self.watch_timer:start(100, 0, function()
        vim.schedule(function()
          vim.cmd.checktime()
        end)
      end)
    end
  end)

  log:debug("File watcher started on %s", cwd)
end

---Stop the file watcher
---@return nil
function CLI:_stop_watcher()
  if self.watch_timer then
    self.watch_timer:stop()
    self.watch_timer:close()
    self.watch_timer = nil
  end
  if self.watcher then
    self.watcher:stop()
    self.watcher:close()
    self.watcher = nil
  end
end

--=============================================================================
-- Public API
-- =============================================================================

---Return the first visible CLI instance, or nil
---@return CodeCompanion.CLI|nil
function CLI.get_visible()
  for _, instance in pairs(clis) do
    if instance.ui:is_visible() then
      return instance
    end
  end
  return nil
end

---Check if any CLI instance is currently visible
---@return boolean
function CLI.is_visible()
  return CLI.get_visible() ~= nil
end

---Toggle the CLI terminal buffer
---@param args? { agent?: string }
---@return nil
function CLI.toggle(args)
  args = args or {}

  local instance = CLI.last_cli()

  if not instance then
    instance = CLI.create({ agent = args.agent })
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
