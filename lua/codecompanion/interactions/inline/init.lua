--[[
The Inline Interaction - This is where code is applied directly to a Neovim buffer
--]]

---@class CodeCompanion.Inline
---@field id number The ID of the inline prompt
---@field adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter The adapter to use for the inline prompt
---@field aug number The ID for the autocmd group
---@field buffer_context CodeCompanion.BufferContext
---@field bufnr number The buffer number to apply the inline edits to
---@field diff_ui? CodeCompanion.DiffUI The diff UI instance
---@field opts table
---@field prompts table The prompts to send to the LLM
---@field request? CodeCompanion.Inline.HTTP|CodeCompanion.Inline.ACP The request that's being processed
---@field requesting? boolean Whether the LLM is working on the prompt, so the finish event fires once
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

---@class CodeCompanion.Inline.Result
---@field lines? string[] The buffer with the LLM's edits applied
---@field reply? string The LLM's text reply, when it made no edits
---@field error? string

local acp = require("codecompanion.interactions.inline.adapters.acp")
local adapter_utils = require("codecompanion.adapters.utils")
local adapters = require("codecompanion.adapters")
local config = require("codecompanion.config")
local editor_context = require("codecompanion.interactions.inline.editor_context")
local http = require("codecompanion.interactions.inline.adapters.http")
local inline_utils = require("codecompanion.interactions.inline.utils")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local tokens = require("codecompanion.utils.tokens")
local ui = require("codecompanion.interactions.inline.ui")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local user_role = config.constants.USER_ROLE

local CONSTANTS = {
  AUTOCMD_GROUP = "codecompanion.inline",
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
    prompts = args.prompts,
  }, { __index = Inline })

  local picked = ui.get_picked_adapter(self.bufnr)
  if args.adapter then
    self.adapter = adapters.resolve(args.adapter)
  elseif picked then
    self.adapter = adapters.resolve(picked.adapter, { model = picked.model })
  else
    self.adapter = adapters.resolve(vim.g.codecompanion_adapter or config.interactions.inline.adapter)
  end
  if not self.adapter then
    return log:error("[Inline] No adapter found")
  end

  return self
end

---Parse special syntax from user prompt (adapters and maintain editor context)
---@param prompt string
---@return string The cleaned prompt
function Inline:parse_special_syntax(prompt)
  local adapter_pattern = "adapter=([%w_]+)"
  local name = prompt:match(adapter_pattern)
  if not name then
    return vim.trim(prompt)
  end

  if config.adapters.http[name] or config.adapters.acp[name] then
    self.adapter = adapters.resolve(name)
    prompt = prompt:gsub(adapter_pattern, "", 1)
  else
    utils.notify("Adapter not found: " .. name, vim.log.levels.ERROR)
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
  if self.adapter.type == "http" and not self.adapter.opts.tools then
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

  return self:submit(messages)
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
  return { lines = lines, context = context, editable = self.buffer_context.is_visual and selection or context }
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
      inline_utils.get_text(target.lines, target.editable)
    )
end

---Form the messages for the request, starting with the buffer
---@param target CodeCompanion.Inline.Target
---@param user_prompt? string
---@return table
function Inline:make_messages(target, user_prompt)
  local messages = {
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
  return vim
    .iter(self.prompts or {})
    :filter(function(prompt)
      local is_blocked = prompt.opts and prompt.opts.contains_code and not config.can_send_code()
      return not is_blocked and (not prompt.condition or prompt.condition(self.buffer_context))
    end)
    :map(function(prompt)
      local content = prompt.content
      return {
        role = prompt.role,
        content = type(content) == "function" and content(self.buffer_context) or content,
        opts = prompt.opts or {},
      }
    end)
    :totable()
end

---Submit the messages to the LLM to process
---@param messages table
---@return nil
function Inline:submit(messages)
  keymaps
    .new({
      bufnr = self.bufnr,
      callbacks = require("codecompanion.interactions.inline.keymaps"),
      data = self,
      keymaps = config.interactions.inline.keymaps,
    })
    :set({ keymaps = { "stop" } })

  self.requesting = true
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

  self.request = (self.adapter.type == "acp" and acp or http).new({ inline = self })
  self.request:submit(messages, {
    on_done = function(result)
      self:done(result)
    end,
  })
end

---Stop the current request
---@return nil
function Inline:stop()
  if self.request then
    self.request:stop()
    self:reset()
  end
end

---Show the edits in a diff, or write them straight to the buffer if the user always accepts them
---@param new_content string[]
---@return nil
function Inline:review(new_content)
  log:debug("[Inline] Starting diff")

  if not vim.deep_equal(api.nvim_buf_get_lines(self.bufnr, 0, -1, false), self.target.lines) then
    log:error("[Inline] The buffer changed while waiting for the LLM, so its edits were not applied")
    return self:reset()
  end

  local approvals = require("codecompanion.interactions.chat.tools.approvals")

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

  self:reset()
end

---Fire `InlineAccepted` if the user kept any of the LLM's edits
---@return nil
function Inline:fire_accepted()
  if not vim.deep_equal(api.nvim_buf_get_lines(self.bufnr, 0, -1, false), self.target.lines) then
    utils.fire("InlineAccepted", { id = self.id, bufnr = self.bufnr })
  end
end

---Review the LLM's edits, or show its text reply
---@param result CodeCompanion.Inline.Result
---@return nil
function Inline:done(result)
  require("codecompanion.interactions.inline.keymaps").clear_map(config.interactions.inline.keymaps, self.bufnr)

  if result.error then
    log:error("[Inline] %s", result.error)
    return self:reset()
  end

  if result.reply then
    self:reset()
    return ui.show_reply(result.reply, { adapter = self.adapter })
  end

  self:finish_request()
  return vim.schedule(function()
    self:review(result.lines)
  end)
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
  self.request = nil
  self.diff_ui = nil
  api.nvim_clear_autocmds({ group = self.aug })
  self:finish_request()
end

return Inline
