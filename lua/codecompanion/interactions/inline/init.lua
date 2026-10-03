--[[
The Inline Interaction - This is where code is applied directly to a Neovim buffer
--]]

---@class CodeCompanion.Inline
---@field id number The ID of the inline prompt
---@field adapter CodeCompanion.HTTPAdapter The adapter to use for the inline prompt
---@field aug number The ID for the autocmd group
---@field buffer_context CodeCompanion.BufferContext
---@field bufnr number The buffer number to apply the inline edits to
---@field current_request? table The current request that's being processed
---@field diff_ui? CodeCompanion.DiffUI The diff UI instance
---@field opts table
---@field prompts table The prompts to send to the LLM
---@field requesting? boolean Whether the LLM is working on the prompt, so the start and finish events fire once
---@field retries number How many times a failed edit has been sent back to the LLM
---@field streaming? boolean The adapter's stream setting before inline turned it off
---@field target CodeCompanion.Inline.Target

---@class CodeCompanion.InlineArgs
---@field adapter? CodeCompanion.HTTPAdapter
---@field buffer_context? CodeCompanion.BufferContext
---@field opts? table
---@field prompts? table The prompts to send to the LLM

---@class CodeCompanion.Inline.Target
---@field lines string[] Every line in the buffer when the prompt was made
---@field context { first: number, last: number } The lines shared with the LLM
---@field editable { first: number, last: number } The lines the LLM is allowed to edit
---@field edited string The editable lines with every successful edit applied

local adapter_utils = require("codecompanion.adapters.utils")
local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local editor_context = require("codecompanion.interactions.inline.editor_context")
local inline_utils = require("codecompanion.interactions.inline.utils")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local replace = require("codecompanion.interactions.chat.tools.builtin.edit_file.replace")
local tokens = require("codecompanion.utils.tokens")
local ui = require("codecompanion.interactions.inline.ui")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local user_role = config.constants.USER_ROLE
local llm_role = config.constants.LLM_ROLE

local CONSTANTS = {
  AUTOCMD_GROUP = "codecompanion.inline",
  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  MAX_RETRIES = 1,

  SYSTEM_PROMPT = [[You are a knowledgeable developer working in the Neovim text editor. You edit %s code on behalf of a user, directly in their active Neovim buffer.

- Follow the user's prompt, enclosed in <prompt></prompt> tags
- Make changes to the buffer by calling the `edit_file` tool, once per change
- Only edit the code you have been told you can edit
- Preserve the exact indentation (tabs/spaces) of the surrounding code
- If the prompt is a question, or can't be answered by editing the buffer, reply in %s without calling the tool]],
}

---@class CodeCompanion.Inline
local Inline = {}

---@param args CodeCompanion.InlineArgs
function Inline.new(args)
  log:trace("[Inline] Initiating with args: %s", args)

  local id = math.random(10000000)

  local self = setmetatable({
    id = id,
    aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. id, {
      clear = false,
    }),
    buffer_context = args.buffer_context,
    bufnr = args.buffer_context.bufnr,
    opts = args.opts or {},
    prompts = vim.deepcopy(args.prompts),
    retries = 0,
  }, { __index = Inline })

  self:set_adapter(args.adapter or config.interactions.inline.adapter)
  if not self.adapter then
    return log:error("[Inline] No adapter found")
  end
  if self.adapter.type ~= "http" then
    return log:warn("Only HTTP adapters are supported for inline interactions")
  end

  -- Check if the user has manually overridden the adapter
  if vim.g.codecompanion_adapter and self.adapter.name ~= vim.g.codecompanion_adapter then
    self:set_adapter(config.adapters[vim.g.codecompanion_adapter])
  end

  local picked = ui.get_picked_adapter(self.bufnr)
  if picked and not args.adapter then
    self.adapter = adapters.resolve(picked.adapter, { model = picked.model })
  end

  return self
end

---Set the adapter for the inline prompt
---@param adapter CodeCompanion.HTTPAdapter|string|function
---@return nil
function Inline:set_adapter(adapter)
  if not self.adapter or not adapters.resolved(adapter) then
    self.adapter = adapters.resolve(adapter)
  end
end

---Set keymaps for the inline interaction
---@param bufnr? number
---@param opts? table
---@return nil
function Inline:set_keymaps(bufnr, opts)
  keymaps
    .new({
      bufnr = bufnr,
      callbacks = require("codecompanion.interactions.inline.keymaps"),
      data = self,
      keymaps = config.interactions.inline.keymaps,
    })
    :set(opts)
end

---Parse special syntax from user prompt (adapters and maintain editor context)
---@param prompt string
---@return string The cleaned prompt
function Inline:parse_special_syntax(prompt)
  local adapter_pattern = "adapter=([%w_]+)"
  local adapter_match = prompt:match(adapter_pattern)

  local config_adapters = vim.tbl_deep_extend("force", {}, config.adapters.acp, config.adapters.http)
  if adapter_match then
    if config_adapters[adapter_match] then
      self:set_adapter(adapter_match)
      prompt = prompt:gsub(adapter_pattern, "", 1) -- Remove only the first occurrence
    else
      utils.notify("Adapter not found: " .. adapter_match, vim.log.levels.ERROR)
    end
  else
    -- Handle legacy first-word adapter detection for backward compatibility
    local split = vim.split(prompt, " ")
    local first_word = split[1]
    if config_adapters[first_word] then
      self:set_adapter(first_word)
      table.remove(split, 1)
      prompt = table.concat(split, " ")
    end
  end

  return vim.trim(prompt)
end

---Prompt the LLM
---@param user_prompt? string
---@return nil
function Inline:prompt(user_prompt)
  log:trace("[Inline] Starting")

  if user_prompt then
    user_prompt = self:parse_special_syntax(user_prompt)
  end

  -- From the prompt library, user's can explicitly ask to be prompted for input
  if self.opts.user_prompt then
    return ui.open_input(self, {
      on_submit = function(input)
        log:info("[Inline] User input received: %s", input)
        self:send_prompt({ user_prompt = user_prompt, input = input })
      end,
    })
  end

  return self:send_prompt({ user_prompt = user_prompt })
end

---Build the messages for the prompt and send them, once the adapter is settled
---@param opts { user_prompt?: string, input?: string }
---@return nil
function Inline:send_prompt(opts)
  if not self.adapter.opts.tools then
    return log:error(
      "[Inline] The %s adapter can't call tools, which inline needs to edit the buffer",
      self.adapter.formatted_name
    )
  end
  if not config.can_send_code() then
    return log:error("[Inline] Sending code is disabled, so inline can't share the buffer it needs to edit")
  end

  local target = self:get_target()
  if not target then
    return
  end
  self.target = target

  local messages = self:make_messages(target, opts.user_prompt)
  if opts.input then
    table.insert(
      messages,
      { role = user_role, content = "<prompt>" .. opts.input .. "</prompt>", opts = { visible = true } }
    )
  end

  self.prompts = messages
  return self:submit(vim.deepcopy(messages))
end

---Work out which lines are shared with the LLM and which lines it can edit
---@return CodeCompanion.Inline.Target|nil
function Inline:get_target()
  local lines = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local max_tokens = inline_utils.get_max_tokens(self.adapter)

  local selection = { first = self.buffer_context.start_line, last = self.buffer_context.end_line }
  local selection_tokens = tokens.calculate(inline_utils.get_text(lines, selection))
  if selection_tokens > max_tokens then
    return log:error(
      "[Inline] The selection is around %d tokens, which is over the %d token limit for inline. Select less code",
      selection_tokens,
      max_tokens
    )
  end

  local context = inline_utils.get_lines_to_send(lines, { around = selection, max_tokens = max_tokens })
  local editable = self.buffer_context.is_visual and selection or context

  return {
    lines = lines,
    context = context,
    editable = editable,
    edited = inline_utils.get_text(lines, editable),
  }
end

---Share the buffer with the LLM, and the lines it can edit if that isn't all of it
---@param target CodeCompanion.Inline.Target
---@return string
function Inline:format_target(target)
  local filetype = self.buffer_context.filetype
  local name = vim.fn.fnamemodify(api.nvim_buf_get_name(self.bufnr), ":.")

  local shared_lines = (target.context.first == 1 and target.context.last == #target.lines) and "the whole buffer"
    or fmt("lines %d-%d of %d", target.context.first, target.context.last, #target.lines)

  local content = fmt(
    "This is %s from `%s`:\n\n````%s\n%s\n````",
    shared_lines,
    name ~= "" and name or "[No Name]",
    filetype,
    inline_utils.get_text(target.lines, target.context)
  )

  if vim.deep_equal(target.editable, target.context) then
    return content .. "\n\nYou can edit any of this code."
  end

  return content
    .. fmt(
      "\n\nYou can only edit lines %d-%d, shown below. Edits to any other code will fail:\n\n````%s\n%s\n````",
      target.editable.first,
      target.editable.last,
      filetype,
      target.edited
    )
end

---Form the messages for the request, starting with the system prompt and the buffer
---@param target CodeCompanion.Inline.Target
---@param user_prompt? string
---@return table
function Inline:make_messages(target, user_prompt)
  local messages = {
    {
      role = config.constants.SYSTEM_ROLE,
      content = fmt(CONSTANTS.SYSTEM_PROMPT, self.buffer_context.filetype, config.opts.language),
      _meta = { tag = "system_tag" },
      opts = { visible = false },
    },
    {
      role = user_role,
      content = self:format_target(target),
      _meta = { tag = "buffer" },
      opts = { visible = false },
    },
  }

  vim.list_extend(messages, self:get_prompt_library_messages())

  if user_prompt then
    local ec = editor_context.new({ inline = self, prompt = user_prompt })
    local found = ec:find():replace():output()
    for _, item in ipairs(found or {}) do
      table.insert(messages, { role = user_role, content = item, opts = { visible = false } })
    end
    table.insert(
      messages,
      { role = user_role, content = "<prompt>" .. ec.prompt .. "</prompt>", opts = { visible = true } }
    )
  end

  return messages
end

---The prompt library entry's messages, with conditions checked and functions expanded
---@return table
function Inline:get_prompt_library_messages()
  local prompts = {}

  for _, prompt in ipairs(self.prompts or {}) do
    if prompt.opts and prompt.opts.contains_code and not config.can_send_code() then
      goto continue
    end
    if prompt.condition and not prompt.condition(self.buffer_context) then
      goto continue
    end
    if type(prompt.content) == "function" then
      prompt.content = prompt.content(self.buffer_context)
    end
    table.insert(prompts, {
      role = prompt.role,
      content = prompt.content,
      opts = prompt.opts or {},
    })
    ::continue::
  end

  return prompts
end

---Submit the messages to the LLM to process
---@param messages table
---@return nil
function Inline:submit(messages)
  self:set_keymaps(self.bufnr, { keymaps = { "stop" } })

  if not self.requesting then
    self.requesting = true
    self.streaming = self.adapter.opts.stream
    utils.fire("InlineStarted", {
      id = self.id,
      bufnr = self.bufnr,
      adapter = {
        name = self.adapter.name,
        formatted_name = self.adapter.formatted_name,
        model = adapter_utils.model(self.adapter),
      },
      range = { editable = self.target.editable, sent = self.target.context },
    })
  end
  self.adapter.opts.stream = false

  local function clear_stop_keymap()
    require("codecompanion.interactions.inline.keymaps").clear_map(config.interactions.inline.keymaps, self.bufnr)
  end

  local adapter = self.adapter
  self.current_request = client.new({ adapter = adapter:map_schema_to_params() }):send(
    { messages = adapter:map_roles(vim.deepcopy(messages)), tools = { { edit_file = inline_utils.get_tool_schema() } } },
    {
      on_done = function(data)
        clear_stop_keymap()
        self:done({ messages = messages, response = self:parse_response(data) })
      end,
      on_error = function(err)
        clear_stop_keymap()
        log:error("[Inline] Request failed with error %s", type(err) == "table" and err.message or err)
        self:reset()
      end,
      bufnr = self.bufnr,
      buffer_context = self.buffer_context or {},
      interaction = "inline",
    }
  )
end

---Stop the current request
---@return nil
function Inline:stop()
  if self.current_request then
    self.current_request.cancel()
    adapters.call_handler(self.adapter, "on_exit")
    self:reset()
  end
end

---@param data table
---@return { content: string, reasoning: table, tool_calls: table, error?: string }
function Inline:parse_response(data)
  local response = { content = "", reasoning = {}, tool_calls = {} }

  local result = adapters.call_handler(self.adapter, "parse_chat", { data = data, tools = response.tool_calls })
  if result and result.extra and adapters.get_handler(self.adapter, "parse_meta") then
    result = adapters.call_handler(self.adapter, "parse_meta", { data = result })
  end
  if not result or result.status ~= CONSTANTS.STATUS_SUCCESS then
    response.error = result and result.output or "No response from the LLM"
    return response
  end

  response.content = vim.trim(result.output.content or "")
  if result.output.reasoning then
    table.insert(response.reasoning, result.output.reasoning)
  end
  return response
end

---Apply each tool call, in order, to the editable lines
---@param tool_calls table
---@return { tool_call: table, status: string, output: string }[]
function Inline:apply_edits(tool_calls)
  local results = {}

  for _, tool_call in ipairs(tool_calls) do
    local decoded = inline_utils.decode_args(tool_call)
    local edit = decoded.error and { error = decoded.error }
      or replace.apply(self.target.edited, {
        old_string = decoded.args.old_string,
        new_string = decoded.args.new_string,
        -- Weaker models send booleans as strings when the provider doesn't enforce the schema
        replace_all = decoded.args.replace_all == true or decoded.args.replace_all == "true",
      })

    if edit.error then
      table.insert(results, { tool_call = tool_call, status = CONSTANTS.STATUS_ERROR, output = edit.error })
    else
      self.target.edited = edit.content
      table.insert(results, { tool_call = tool_call, status = CONSTANTS.STATUS_SUCCESS, output = "Edit applied" })
    end
  end

  return results
end

---Show the edits in a diff, or write them straight to the buffer if the user always accepts them
---@return nil
function Inline:review()
  log:debug("[Inline] Starting diff")

  if not vim.deep_equal(api.nvim_buf_get_lines(self.bufnr, 0, -1, false), self.target.lines) then
    log:error("[Inline] The buffer changed while waiting for the LLM, so its edits were not applied")
    return self:reset()
  end

  local approvals = require("codecompanion.interactions.chat.tools.approvals")
  local new_content = inline_utils.get_new_content(self.target)

  if not config.display.diff.enabled or approvals:is_approved(self.bufnr, { tool_name = "inline" }) then
    api.nvim_buf_set_lines(self.bufnr, 0, -1, false, new_content)
    self:fire_accepted()
    return self:reset()
  end

  local helpers = require("codecompanion.helpers")
  self.diff_ui = helpers.show_diff({
    bufnr = self.bufnr,
    from_lines = self.target.lines,
    to_lines = new_content,
    diff_id = self.id,
    ft = self.buffer_context.filetype,
    inline = true,
    hunk_actions = true,
    banner = ui.build_diff_banner(),
    keymaps = {
      on_accept = function(diff_ui)
        self:on_diff_accepted(diff_ui)
      end,
      on_reject = function(diff_ui)
        self:on_diff_rejected(diff_ui)
      end,
      on_always_accept = function()
        approvals:always(self.bufnr, { tool_name = "inline" })
      end,
    },
  })
end

---@param diff_ui CodeCompanion.DiffUI
---@return nil
function Inline:on_diff_accepted(diff_ui)
  log:trace("[Inline] Diff accepted for id=%s", self.id)
  -- A formatter listening for the event would otherwise format the spacer line and the drawn hunks
  diff_ui:remove_inline_marks()
  self:fire_accepted()
  self.diff_ui = nil
  self:reset()
end

---Reject the hunks that are left, keeping any the user has already accepted
---@param diff_ui CodeCompanion.DiffUI
---@return nil
function Inline:on_diff_rejected(diff_ui)
  log:trace("[Inline] Diff rejected for id=%s", self.id)

  if api.nvim_buf_is_valid(self.bufnr) then
    -- The spacer line is found by extmark, which replacing every line would move
    diff_ui:remove_inline_marks()
    api.nvim_buf_set_lines(self.bufnr, 0, -1, false, diff_ui.diff.from.lines)
    self:fire_accepted()
  end

  self.diff_ui = nil
  self:reset()
end

---Fire `InlineAccepted` if the user kept any of the LLM's edits
---@return nil
function Inline:fire_accepted()
  if not vim.deep_equal(api.nvim_buf_get_lines(self.bufnr, 0, -1, false), self.target.lines) then
    utils.fire("InlineAccepted", { id = self.id, bufnr = self.bufnr })
  end
end

---Apply the LLM's edits, sending any failures back to it, or route a text reply to the chat buffer
---@param args { messages: table, response: table }
---@return nil
function Inline:done(args)
  local response = args.response
  if response.error then
    log:error("[Inline] %s", response.error)
    return self:reset()
  end

  if vim.tbl_isempty(response.tool_calls) then
    self:reset()
    if response.content == "" then
      return log:error("[%s] Returned no edits and no reply", self.adapter.formatted_name)
    end
    return ui.show_reply(self, response.content)
  end

  response.tool_calls = adapters.call_handler(self.adapter, "format_calls", { tools = response.tool_calls })
  local results = self:apply_edits(response.tool_calls)
  local failed = vim.tbl_filter(function(result)
    return result.status == CONSTANTS.STATUS_ERROR
  end, results)

  if vim.tbl_isempty(failed) then
    self:finish_request()
    return vim.schedule(function()
      self:review()
    end)
  end

  if self.retries >= CONSTANTS.MAX_RETRIES then
    log:error("[%s] Could not edit the buffer: %s", self.adapter.formatted_name, failed[1].output)
    return self:reset()
  end

  self.retries = self.retries + 1
  log:debug("[Inline] Retrying after %d failed edit(s)", #failed)
  return self:submit(self:add_tool_results(args.messages, { response = response, results = results }))
end

---Add the LLM's tool calls and their results to the messages, ready to send back
---@param messages table
---@param args { response: table, results: table }
---@return table
function Inline:add_tool_results(messages, args)
  messages = vim.deepcopy(messages)

  table.insert(messages, {
    role = llm_role,
    content = args.response.content,
    reasoning = inline_utils.join_reasoning(self.adapter, args.response.reasoning),
    tools = { calls = args.response.tool_calls },
    opts = { visible = false },
  })

  for _, result in ipairs(args.results) do
    local output = result.status == CONSTANTS.STATUS_ERROR and fmt("Edit failed: %s", result.output) or result.output
    local message = adapters.call_handler(self.adapter, "format_response", {
      tool_call = result.tool_call,
      output = output,
    })
    if message then
      table.insert(messages, message)
    end
  end

  return messages
end

---Fire `InlineFinished` once the LLM is done with the prompt, however it ended
---@return nil
function Inline:finish_request()
  if not self.requesting then
    return
  end
  self.requesting = false
  utils.fire("InlineFinished", { id = self.id, bufnr = self.bufnr })
end

---Reset the inline prompt class
---@return nil
function Inline:reset()
  self.adapter.opts.stream = self.streaming
  self.current_request = nil
  api.nvim_clear_autocmds({ group = self.aug })
  self:finish_request()
end

return Inline
