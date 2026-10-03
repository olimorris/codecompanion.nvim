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

local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local editor_context = require("codecompanion.interactions.inline.editor_context")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local replace = require("codecompanion.interactions.chat.tools.builtin.edit_file.replace")
local shared = require("codecompanion.adapters.shared")
local tokens = require("codecompanion.utils.tokens")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local user_role = config.constants.USER_ROLE
local llm_role = config.constants.LLM_ROLE

local CONSTANTS = {
  AUTOCMD_GROUP = "codecompanion.inline",
  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  MAX_CONTEXT_TOKENS = 16000,
  MAX_RETRIES = 1,
  RESERVED_TOKENS = 3000,

  SYSTEM_PROMPT = [[You are a knowledgeable developer working in the Neovim text editor. You edit %s code on behalf of a user, directly in their active Neovim buffer.

- Follow the user's prompt, enclosed in <prompt></prompt> tags
- Make changes to the buffer by calling the `edit_file` tool, once per change
- Only edit the code you have been told you can edit
- Preserve the exact indentation (tabs/spaces) of the surrounding code
- If the prompt is a question, or can't be answered by editing the buffer, reply in %s without calling the tool]],

  TOOL_DESCRIPTION = [[Edit the user's buffer by replacing an exact string with new text.

- `old_string` must match the buffer exactly, including whitespace and indentation
- The edit fails if `old_string` appears more than once in the code you can edit. Include more surrounding lines to make it unique, or set `replace_all` to change every occurrence
- Keep `old_string` short: usually 2-4 lines that uniquely identify the text to change
- To insert code, include the neighbouring lines in `old_string` and repeat them in `new_string` alongside the new code
- To delete text, set `new_string` to an empty string]],
}

---The `edit_file` schema, scoped to the one buffer that inline edits
---@return table
local function get_tool_schema()
  local schema = vim.deepcopy(require("codecompanion.interactions.chat.tools.builtin.edit_file").schema)
  local tool = schema["function"]
  tool.description = CONSTANTS.TOOL_DESCRIPTION
  tool.parameters.properties.filepath = nil
  tool.parameters.required = vim.tbl_filter(function(name)
    return name ~= "filepath"
  end, tool.parameters.required)
  return schema
end

---@param lines string[]
---@param range { first: number, last: number }
---@return string
local function get_text(lines, range)
  return table.concat(vim.list_slice(lines, range.first, range.last), "\n")
end

---Grow the range a line at a time, above and below, until the next line would exceed the limit
---@param lines string[]
---@param opts { range: { first: number, last: number }, max_tokens: number }
---@return { first: number, last: number }
local function grow_range(lines, opts)
  local first, last = opts.range.first, opts.range.last
  local used = tokens.calculate(get_text(lines, opts.range))

  local function try_line(index)
    local cost = tokens.calculate(lines[index])
    if used + cost > opts.max_tokens then
      return false
    end
    used = used + cost
    return true
  end

  local grew = true
  while grew do
    grew = false
    if first > 1 and try_line(first - 1) then
      first, grew = first - 1, true
    end
    if last < #lines and try_line(last + 1) then
      last, grew = last + 1, true
    end
  end

  return { first = first, last = last }
end

---@param adapter CodeCompanion.HTTPAdapter
---@return number
local function get_max_tokens(adapter)
  local configured = config.interactions.inline.opts and config.interactions.inline.opts.max_context_tokens
  if configured then
    return configured
  end

  local input_limit = shared.input_limit(adapter)
  if not input_limit then
    return CONSTANTS.MAX_CONTEXT_TOKENS
  end
  return math.min(CONSTANTS.MAX_CONTEXT_TOKENS, input_limit - CONSTANTS.RESERVED_TOKENS)
end

---Join the reasoning from a response so it can be sent back alongside its tool calls
---@param adapter CodeCompanion.HTTPAdapter
---@param reasoning table
---@return string|table|nil
local function join_reasoning(adapter, reasoning)
  if vim.tbl_isempty(reasoning) then
    return nil
  end
  if vim.iter(reasoning):any(function(item)
    return type(item) ~= "string"
  end) then
    return adapters.call_handler(adapter, "build_reasoning", { data = reasoning })
  end
  return table.concat(reasoning, "")
end

---@param tool_call table
---@return { args?: table, error?: string }
local function decode_arguments(tool_call)
  local args = tool_call["function"] and tool_call["function"].arguments
  if type(args) == "string" then
    local ok, decoded = pcall(vim.json.decode, args ~= "" and args or "{}")
    if not ok then
      return { error = fmt("The arguments could not be decoded as JSON: %s", decoded) }
    end
    args = decoded
  end
  if type(args) ~= "table" then
    return { error = "The arguments must be a JSON object with `old_string`, `new_string` and `replace_all` keys" }
  end
  if type(args.old_string) ~= "string" or type(args.new_string) ~= "string" then
    local keys = vim.tbl_map(function(key)
      return fmt("`%s`", tostring(key):sub(1, 30))
    end, vim.tbl_keys(args))
    table.sort(keys)
    return {
      error = fmt(
        "`old_string` and `new_string` must both be strings, but the keys you sent were %s",
        table.concat(keys, ", ")
      ),
    }
  end
  return { args = args }
end

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

---Work out which lines are shared with the LLM and which lines it can edit
---@return { target?: CodeCompanion.Inline.Target, error?: string }
function Inline:make_target()
  local lines = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local max_tokens = get_max_tokens(self.adapter)

  local selection = { first = self.buffer_context.start_line, last = self.buffer_context.end_line }
  local selection_tokens = tokens.calculate(get_text(lines, selection))
  if selection_tokens > max_tokens then
    return {
      error = fmt(
        "The selection is around %d tokens, which is over the %d token limit for inline. Select less code",
        selection_tokens,
        max_tokens
      ),
    }
  end

  local context = grow_range(lines, { range = selection, max_tokens = max_tokens })
  local editable = self.buffer_context.is_visual and selection or context

  return {
    target = {
      lines = lines,
      context = context,
      editable = editable,
      edited = get_text(lines, editable),
    },
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
    get_text(target.lines, target.context)
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

  vim.list_extend(messages, self:make_ext_prompts())

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

---Prompt the LLM
---@param user_prompt? string The prompt supplied by the user
---@return nil
function Inline:prompt(user_prompt)
  log:trace("[Inline] Starting")

  if user_prompt then
    user_prompt = self:parse_special_syntax(user_prompt)
  end

  if not self.adapter.opts.tools then
    return log:error(
      "[Inline] The %s adapter can't call tools, which inline needs to edit the buffer",
      self.adapter.formatted_name
    )
  end
  if not config.can_send_code() then
    return log:error("[Inline] Sending code is disabled, so inline can't share the buffer it needs to edit")
  end

  local made = self:make_target()
  if not made.target then
    return log:error("[Inline] %s", made.error)
  end
  self.target = made.target

  local messages = self:make_messages(made.target, user_prompt)

  -- From the prompt library, user's can explicitly ask to be prompted for input
  if self.opts.user_prompt then
    return require("codecompanion.interactions.shared.input").open({
      title = " " .. config.display.input.title .. " ",
      on_submit = function(input)
        log:info("[Inline] User input received: %s", input)
        table.insert(
          messages,
          { role = user_role, content = "<prompt>" .. input .. "</prompt>", opts = { visible = true } }
        )
        self.prompts = messages
        return self:submit(vim.deepcopy(messages))
      end,
    })
  end

  self.prompts = messages
  return self:submit(vim.deepcopy(messages))
end

---Prompts can enter the inline class from numerous external sources such as the
---cmd line and the action palette. We begin to form the payload to send to
---the LLM in this method, checking conditions and expanding functions.
---@return table
function Inline:make_ext_prompts()
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

---Stop the current request
---@return nil
function Inline:stop()
  if self.current_request then
    self.current_request.cancel()
    adapters.call_handler(self.adapter, "on_exit")
    self:reset()
  end
end

local _streaming = true

---Submit the messages to the LLM to process
---@param messages table
---@return nil
function Inline:submit(messages)
  -- Inline editing only works with streaming off - We should remember the current status
  _streaming = self.adapter.opts.stream
  self.adapter.opts.stream = false

  self:set_keymaps(self.bufnr, { keymaps = { "stop" } })

  if not self.requesting then
    self.requesting = true
    utils.fire("InlineStarted", { bufnr = self.bufnr })
  end

  local function clear_stop_keymap()
    require("codecompanion.interactions.inline.keymaps").clear_map(config.interactions.inline.keymaps, self.bufnr)
  end

  local adapter = self.adapter
  self.current_request = client.new({ adapter = adapter:map_schema_to_params() }):send(
    { messages = adapter:map_roles(vim.deepcopy(messages)), tools = { { edit_file = get_tool_schema() } } },
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
    return self:to_chat(response.content)
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

---Apply each tool call, in order, to the editable lines
---@param tool_calls table
---@return { tool_call: table, status: string, output: string }[]
function Inline:apply_edits(tool_calls)
  local results = {}

  for _, tool_call in ipairs(tool_calls) do
    local decoded = decode_arguments(tool_call)
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

---Add the LLM's tool calls and their results to the messages, ready to send back
---@param messages table
---@param args { response: table, results: table }
---@return table
function Inline:add_tool_results(messages, args)
  messages = vim.deepcopy(messages)

  table.insert(messages, {
    role = llm_role,
    content = args.response.content,
    reasoning = join_reasoning(self.adapter, args.response.reasoning),
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
  utils.fire("InlineFinished", { bufnr = self.bufnr })
end

---Reset the inline prompt class
---@return nil
function Inline:reset()
  self.adapter.opts.stream = _streaming
  self.current_request = nil
  api.nvim_clear_autocmds({ group = self.aug })
  self:finish_request()
end

---Open a chat buffer with the user's prompt and the LLM's reply
---@param reply string
---@return CodeCompanion.Chat|nil
function Inline:to_chat(reply)
  local chat_opts = {
    adapter = self.adapter,
    buffer_context = self.buffer_context,
  }

  local rules_cb = require("codecompanion.interactions.shared.rules.helpers").add_callbacks(chat_opts)
  if rules_cb then
    chat_opts.callbacks = rules_cb
  end

  local chat = require("codecompanion.interactions.chat").new(chat_opts)
  if not chat then
    return
  end

  local messages = vim.tbl_filter(function(message)
    return not (message._meta and vim.list_contains({ "system_tag", "buffer" }, message._meta.tag))
  end, self.prompts)
  table.insert(messages, { role = llm_role, content = reply, opts = { visible = true } })

  -- Messages passed to `Chat.new` lose their last entry to the renderer, so they're added one at a time
  for _, message in ipairs(messages) do
    local visible = not (message.opts and message.opts.visible == false)
    chat:add_message({ role = message.role, content = message.content }, { visible = visible })
    if visible then
      chat:add_buf_message({ role = message.role, content = message.content })
    end
  end

  chat._last_role = llm_role
  chat:ready_for_input()
  return chat
end

---The buffer's lines with the edited lines spliced back in
---@return string[]
function Inline:get_new_content()
  local target = self.target
  local new_content = vim.list_slice(target.lines, 1, target.editable.first - 1)
  vim.list_extend(new_content, vim.split(target.edited, "\n", { plain = true }))
  return vim.list_extend(new_content, vim.list_slice(target.lines, target.editable.last + 1))
end

---Build the banner text for the inline diff
---@return string
function Inline:build_diff_banner()
  return fmt("%s for keymaps", config.interactions.shared.keymaps.show_keymaps.modes.n)
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
  local new_content = self:get_new_content()

  if not config.display.diff.enabled or approvals:is_approved(self.bufnr, { tool_name = "inline" }) then
    api.nvim_buf_set_lines(self.bufnr, 0, -1, false, new_content)
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
    banner = self:build_diff_banner(),
    keymaps = {
      on_accept = function()
        self:on_diff_accepted()
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

---Handle diff accepted event
---@return nil
function Inline:on_diff_accepted()
  log:trace("[Inline] Diff accepted for id=%s", self.id)
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
  end

  self.diff_ui = nil
  self:reset()
end

return Inline
