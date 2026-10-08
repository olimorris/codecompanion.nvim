---@class CodeCompanion.Inline.ACP
---@field adapter CodeCompanion.ACPAdapter
---@field copy_path string The temporary copy of the buffer that the agent edits
---@field inline CodeCompanion.Inline
---@field on_done fun(result: CodeCompanion.Inline.Result)
---@field prompt? table The prompt that's being processed
---@field reply string[] The agent's text reply
---@field stopped? boolean

local async = require("codecompanion.utils.async")
local config = require("codecompanion.config")
local file_utils = require("codecompanion.utils.files")
local inline_prompt = require("codecompanion.interactions.inline.prompt")
local log = require("codecompanion.utils.log")

local api = vim.api
local fmt = string.format

local CONSTANTS = {
  ALLOWED_KINDS = { read = true, search = true, think = true, fetch = true },

  EDIT_RULE = "Make changes by editing `%s`, which holds the buffer. Never edit any other file, nor run commands",
}

local _connection
local _running
local _sessions = {}

---Connect to the agent, replacing a connection to a different agent
---@param adapter CodeCompanion.ACPAdapter
---@return CodeCompanion.ACP.Connection|nil
local function connect(adapter)
  if _connection and _connection.adapter.name ~= adapter.name then
    _connection:disconnect()
    _connection = nil
  end
  if _connection and _connection:is_ready() then
    return _connection
  end

  -- A new or restarted agent process doesn't know the sessions it had before
  _sessions = {}
  _connection = _connection or require("codecompanion.acp").new({ adapter = adapter })
  if not _connection:connect_and_authenticate() then
    _connection = nil
    return nil
  end

  return _connection
end

---Connect and switch to the buffer's own session, creating one the first time
---@param opts { adapter: CodeCompanion.ACPAdapter, bufnr: number }
---@return CodeCompanion.ACP.Connection|nil
local function connect_to_buffer_session(opts)
  local connection = connect(opts.adapter)
  if not connection then
    return nil
  end

  local bufnr = opts.bufnr
  connection:use_session(_sessions[bufnr])
  if not connection:ensure_session() then
    return nil
  end

  if not _sessions[bufnr] then
    -- The inline adapter, not the connection's, carries the model picked for this buffer
    require("codecompanion.interactions.chat.acp.defaults").apply(opts.adapter, connection)
    api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        _sessions[bufnr] = nil
      end,
    })
  end

  _sessions[bufnr] = connection.session_id
  return connection
end

---@class CodeCompanion.Inline.ACP
local ACP = {}

---@param args { inline: CodeCompanion.Inline }
---@return CodeCompanion.Inline.ACP
function ACP.new(args)
  return setmetatable({
    adapter = args.inline.adapter,
    inline = args.inline,
    reply = {},
  }, { __index = ACP })
end

---The agent makes inline edits to a copy of the buffer
---@param messages table
---@param opts { on_done: fun(result: CodeCompanion.Inline.Result) }
---@return nil
function ACP:submit(messages, opts)
  self.on_done = opts.on_done

  if _running then
    return self.on_done({ error = fmt("%s is still working on another inline prompt", _running.adapter.formatted_name) })
  end
  _running = self

  self.copy_path = self:make_copy()

  async.sync(function()
    local connection = connect_to_buffer_session({ adapter = self.adapter, bufnr = self.inline.bufnr })
    if not connection then
      return self:finish({ error = fmt("Could not connect to %s", self.adapter.formatted_name) })
    end
    -- Stopping while connecting deleted the copy, so a prompt sent now would offer to empty the buffer
    if self.stopped then
      return
    end

    self.prompt = connection
      :session_prompt({
        { role = config.constants.USER_ROLE, content = self:make_prompt(messages), _meta = {} },
      })
      :on_message_chunk(function(text)
        table.insert(self.reply, text)
      end)
      :on_permission_request(function(request)
        self:respond_to_permission(request)
      end)
      :on_write_text_file_request(function(request)
        return self:is_copy(request.path)
      end)
      :on_complete(function(stop_reason)
        self:complete(stop_reason)
      end)
      :on_error(function(err)
        self:finish({ error = err })
      end)
      :with_options({ bufnr = self.inline.bufnr, interaction = "inline" })
      :send()
  end)()
end

---List the agent's models for the buffer's session, which must run inside a coroutine
---@param opts { adapter: CodeCompanion.ACPAdapter, bufnr: number }
---@return { availableModels: { modelId: string, name: string }[], currentModelId: string }|nil
function ACP.list_models(opts)
  -- Switching sessions mid-prompt would leave the agent's replies with nowhere to go
  if _running then
    return log:warn("[Inline] %s is still working on an inline prompt", _running.adapter.formatted_name)
  end
  local connection = connect_to_buffer_session(opts)
  return connection and connection:get_models()
end

---Change the model of the buffer's session, which must run inside a coroutine
---@param opts { adapter: CodeCompanion.ACPAdapter, bufnr: number, model: string }
---@return nil
function ACP.set_model(opts)
  if _running then
    return log:warn("[Inline] %s is still working on an inline prompt", _running.adapter.formatted_name)
  end
  local connection = connect_to_buffer_session(opts)
  if connection then
    connection:set_model(opts.model)
  end
end

---@return nil
function ACP:stop()
  self.stopped = true
  if self.prompt then
    self.prompt.cancel()
  end
  self:clean_up()
end

---@return nil
function ACP:clean_up()
  self.prompt = nil
  if _running == self then
    _running = nil
  end
  if file_utils.exists(self.copy_path) then
    file_utils.delete(self.copy_path)
  end
end

---@return string
function ACP:make_copy()
  local name = api.nvim_buf_get_name(self.inline.bufnr)
  local path = vim.fs.joinpath(vim.fn.tempname(), name ~= "" and vim.fs.basename(name) or "untitled")
  file_utils.write_to_path(path, table.concat(self.inline.target.lines, "\n") .. "\n")
  return path
end

---@return string[]
function ACP:read_copy()
  local lines = file_utils.read_lines(self.copy_path) or {}
  if lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

---Join the system prompt and the messages into the one prompt that an agent takes
---@param messages table
---@return string
function ACP:make_prompt(messages)
  local sections = {
    inline_prompt.build({
      filetype = self.inline.buffer_context.filetype,
      edit_rule = fmt(CONSTANTS.EDIT_RULE, self.copy_path),
    }),
  }

  for _, message in ipairs(messages) do
    if message.role == config.constants.USER_ROLE or message.role == config.constants.SYSTEM_ROLE then
      table.insert(sections, message.content)
    end
  end

  return table.concat(sections, "\n\n")
end

---Allow reads and edits to the copy, and reject everything else
---@param request table
---@return nil
function ACP:respond_to_permission(request)
  local tool_call = request.tool_call or {}
  local is_allowed = CONSTANTS.ALLOWED_KINDS[tool_call.kind]
    or (tool_call.kind == "edit" and self:is_editing_copy(tool_call))
  local kind = is_allowed and "allow_once" or "reject_once"

  for _, option in ipairs(request.options or {}) do
    if option.kind == kind then
      return request.respond(option.optionId, false)
    end
  end

  log:debug("[Inline] Cancelled a %s permission request with no %s option", tool_call.kind, kind)
  request.respond(nil, true)
end

---@param tool_call table
---@return boolean
function ACP:is_editing_copy(tool_call)
  local paths = {}
  for _, location in ipairs(tool_call.locations or {}) do
    table.insert(paths, location.path)
  end
  for _, content in ipairs(tool_call.content or {}) do
    if content.type == "diff" then
      table.insert(paths, content.path)
    end
  end

  return #paths > 0 and vim.iter(paths):all(function(path)
    return self:is_copy(path)
  end)
end

---@param path string
---@return boolean
function ACP:is_copy(path)
  -- macOS temp files live under /var, which agents may report through its /private/var target
  local function resolve(file_path)
    return vim.uv.fs_realpath(file_path) or vim.fs.normalize(file_path)
  end
  return resolve(path) == resolve(self.copy_path)
end

---Hand back the edited copy, or the agent's reply if it didn't edit
---@param stop_reason? string
---@return nil
function ACP:complete(stop_reason)
  if stop_reason == "canceled" then
    return self:finish({ error = fmt("%s cancelled the prompt", self.adapter.formatted_name) })
  end

  local lines = self:read_copy()
  if not vim.deep_equal(lines, self.inline.target.lines) then
    return self:finish({ lines = lines })
  end

  local reply = vim.trim(table.concat(self.reply))
  if reply == "" then
    return self:finish({ error = fmt("%s returned no edits and no reply", self.adapter.formatted_name) })
  end

  return self:finish({ reply = reply })
end

---@param result CodeCompanion.Inline.Result
---@return nil
function ACP:finish(result)
  if self.stopped then
    return
  end
  self:clean_up()
  vim.schedule(function()
    self.on_done(result)
  end)
end

return ACP
