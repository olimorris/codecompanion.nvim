local config = require("codecompanion.config")
local editor = require("codecompanion.interactions.cli.editor")
local files = require("codecompanion.utils.files")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local markdown = require("codecompanion.utils.markdown")
local registry = require("codecompanion.interactions.shared.registry")
local utils = require("codecompanion.utils")
local watch = require("codecompanion.interactions.shared.watch")

local api = vim.api
local fmt = string.format

---@type table
_G.codecompanion_cli_metadata = {}

---@class CodeCompanion.CLI
---@field agent table
---@field agent_name string
---@field aug number
---@field bufnr number
---@field id number
---@field provider CodeCompanion.CLI.Provider
---@field request_id string|nil
---@field ui CodeCompanion.CLI.UI
local CLI = {}

local clis = {} ---@type table<number, CodeCompanion.CLI>
local last_cli = nil ---@type CodeCompanion.CLI|nil

---@param cli CodeCompanion.CLI
---@return table
local function build_request_payload(cli)
  return {
    id = cli.request_id,
    bufnr = cli.bufnr,
    interaction = "cli",
    adapter = {
      name = cli.agent_name,
      formatted_name = cli.agent.description or cli.agent_name,
      type = "cli",
    },
  }
end

---Open the request that statusline integrations pair with, so a CLI turn shows as in flight
---@param cli CodeCompanion.CLI
---@return nil
local function start_request(cli)
  cli.request_id = tostring(math.random(10000000))
  utils.fire("RequestStarted", build_request_payload(cli))
end

---@param cli CodeCompanion.CLI
---@param opts { status: "success"|"cancelled" }
---@return nil
local function finish_request(cli, opts)
  if not cli.request_id then
    return
  end

  utils.fire("RequestFinished", vim.tbl_extend("force", build_request_payload(cli), { status = opts.status }))
  cli.request_id = nil
end

---@param cli CodeCompanion.CLI
---@return string
local function get_agent_name(cli)
  return cli.agent.description or cli.agent_name
end

---Tell the user a turn has ended, unless they watched it end
---@param cli CodeCompanion.CLI
---@return nil
local function notify_done(cli)
  if config.interactions.cli.opts.notify and not cli.ui:is_active() then
    utils.notify(get_agent_name(cli) .. " finished")
  end
end

---@param cli CodeCompanion.CLI
---@param opts { message: string }
---@return nil
local function notify_waiting(cli, opts)
  if config.interactions.cli.opts.notify and not cli.ui:is_active() then
    utils.notify(fmt("%s: %s", get_agent_name(cli), opts.message))
  end
end

---Read the JSON that an agent's hook received, which the hook script saves to a file
---@param path? string
---@return table
local function read_payload(path)
  if not path then
    return {}
  end

  local ok, payload = pcall(function()
    return vim.json.decode(files.read(path), { luanil = { object = true, array = true } })
  end)
  if not ok then
    log:debug("Could not read the CLI hook payload at %s: %s", path, payload)
    return {}
  end
  return payload
end

---Describe what the agent is waiting on, such as "Permission: Bash: make test"
---@param payload table
---@return string
local function describe_wait(payload)
  if payload.hook_event_name ~= "PermissionRequest" then
    return payload.message or "Waiting for you"
  end

  local tool_input = payload.tool_input or {}
  local target = tool_input.command or tool_input.file_path or tool_input.url or tool_input.pattern
  if type(target) ~= "string" then
    return "Permission: " .. (payload.tool_name or "a tool")
  end
  -- Never truncated, or the cut could hide the end of a command, such as a trailing `| sh`
  return fmt("Permission: %s: %s", payload.tool_name, vim.trim((target:gsub("%s+", " "))))
end

---Respond to each hook event, after the agent's call into Neovim has returned
local hook_handlers = {
  submitted = function(cli)
    utils.fire("CLISubmitted", { bufnr = cli.bufnr })
    start_request(cli)
  end,
  done = function(cli)
    utils.fire("CLIDone", { bufnr = cli.bufnr })
    finish_request(cli, { status = "success" })
    notify_done(cli)
  end,
  approval_requested = function(cli, hook)
    -- Claude Code notifies when its prompt sits idle, which arrives after the turn ended and would show as blocked
    if not cli.request_id then
      return
    end

    local message = describe_wait(hook.payload)
    utils.fire("CLIApprovalRequested", { bufnr = cli.bufnr, message = message })
    -- Claude Code repeats an unanswered permission request as a notification, which the user has already had
    if hook.payload.notification_type ~= "permission_prompt" then
      notify_waiting(cli, { message = message })
    end
  end,
  approval_finished = function(cli)
    utils.fire("CLIApprovalFinished", { bufnr = cli.bufnr })
  end,
}

---Context for a prompt the user typed into the agent, which the hook script hands back to it
---@param opts { event: string }
---@return string
local function build_reply(opts)
  if opts.event == "submitted" and config.interactions.cli.opts.share_editor_state then
    return editor.describe()
  end
  return ""
end

---Keymap callbacks for the CLI buffer
local keymap_callbacks = {
  open_file = {
    callback = function(cli)
      local cursor = api.nvim_win_get_cursor(0)
      local reference = editor.find_reference_at({ bufnr = cli.bufnr, row = cursor[1], col = cursor[2] + 1 })
      if not reference then
        return
      end
      if not files.exists(vim.fs.normalize(reference.path)) then
        return utils.notify(fmt("Could not find `%s`", reference.path), vim.log.levels.WARN)
      end

      local from_winnr = api.nvim_get_current_win()
      if api.nvim_win_get_config(from_winnr).relative ~= "" then
        cli.ui:hide()
      end
      editor.open_file(vim.tbl_extend("force", reference, { from_winnr = from_winnr }))
    end,
  },
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

  -- Before the CLI's window exists, so the user's code window is the one recorded
  editor.track()

  local bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(bufnr, string.format("[CodeCompanion CLI] %d", bufnr))
  vim.bo[bufnr].filetype = "codecompanion_cli"

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

  watch.enable()

  clis[bufnr] = self
  last_cli = self

  registry.add(bufnr, {
    name = agent_name,
    description = agent.description or "CLI agent",
    interaction = "cli",
    open = function(opts)
      opts = opts or {}
      if opts.winnr then
        self.ui:show_in_win(opts)
        return
      end
      self.ui:open()
    end,
    hide = function(opts)
      self.ui:hide(opts)
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

---Resolve any editor context references in a prompt
---@param prompt string
---@param buffer_context CodeCompanion.BufferContext
---@return string
function CLI.resolve_editor_context(prompt, buffer_context)
  local editor_context = require("codecompanion.interactions.shared.editor_context").new("cli")
  local resolved = editor_context:replace_cli(prompt, buffer_context)

  -- A user may make a visual seleection and also include editor context such as
  -- #{this}, which would result in the same context being added twice. To
  -- stop this, we check for any editor context and only then share the
  -- visual selection with the agent.
  if buffer_context.is_visual and buffer_context.lines and #buffer_context.lines > 0 and not prompt:find("#{") then
    resolved = string.format(
      [[- Selected code from @%s (lines %d-%d):
%s
%s]],
      buffer_context.relative_path, -- Keep the CLI
      buffer_context.start_line,
      buffer_context.end_line,
      markdown.form_codeblock(table.concat(buffer_context.lines, "\n"), { ft = buffer_context.filetype or "" }),
      resolved
    )
  end

  return resolved
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

---Focus the CLI window and enter insert mode
---@return nil
function CLI:focus()
  local winnr = self.ui.winnr
  vim.defer_fn(function()
    if winnr and api.nvim_win_is_valid(winnr) then
      api.nvim_set_current_win(winnr)
      vim.schedule(function()
        vim.cmd.startinsert()
      end)
    end
  end, 10)
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
  finish_request(self, { status = "cancelled" })

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

---Hook into a CLI agent, returning what the hook script should print back to it
---@param opts { bufnr: number, event: "submitted"|"done"|"approval_requested"|"approval_finished", payload_path?: string }
---@return string
function CLI.hook(opts)
  local handler = hook_handlers[opts.event]
  if not handler or not clis[opts.bufnr] then
    return ""
  end

  -- The script deletes the payload as soon as this call returns
  local hook = { payload = read_payload(opts.payload_path), reply = build_reply(opts) }

  -- The agent blocks on this call, so let it return before the listeners run
  vim.schedule(function()
    local cli = clis[opts.bufnr]
    if cli then
      handler(cli, hook)
    end
  end)

  return hook.reply
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
