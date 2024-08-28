local adapters = require("codecompanion.adapters")
local client = require("codecompanion.client")
local config = require("codecompanion").config

local hl = require("codecompanion.utils.highlights")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local msg_utils = require("codecompanion.utils.messages")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.util")

local api = vim.api

local CONSTANTS = {
  AUTOCMD_GROUP = "codecompanion.inline",

  PLACEMENT_PROMPT = [[I would like you to assess a prompt which has been made from within the Neovim text editor. Based on this prompt, I require you to determine where the output from this prompt should be placed. I am calling this determination the "<method>". For example, the user may wish for the output to be placed:

1. `replace` the current selection
2. `add` after the current cursor position
3. `new` in a new buffer/file
4. `chat` in a buffer which the user can then interact with

Here are some example prompts and their correct method classification ("<method>") to help you:

- "Can you refactor/fix/amend this code?" would be `replace`
- "Can you create a method/function that does XYZ" would be `add`
- "Can you create a method/function for XYZ and put it in a new buffer?" would be `new`
- "Can you write unit tests for this code?" would be `new` as commonly tests are written in a new file
- "Why is Neovim so popular?" or "What does this code do?" would be `chat` as it requires a conversation and doesn't immediately result in pure code

Please respond to this prompt in the format "<method>", placing the classifiction in a tag. For example "replace" would be `<replace>`, "add" would be `<add>`, "new" would be `<new>` and "chat" would be `<chat>`. If you can't classify the message, reply with `<error>`. Do not provide any other content in your response or you'll break the plugin this is being called from.]],
  CODE_ONLY_PROMPT = [[Respond with code only. DO NOT format the code in Markdown code blocks, DO NOT use backticks AND DO NOT provide any explanations.]],

  USER_ROLE = "user",
  LLM_ROLE = "llm",
  SYSTEM_ROLE = "system",
}

---Format given lines into a code block alongside a prompt
---@param prompt string
---@param filetype string
---@param lines table
---@return string
local function code_block(prompt, filetype, lines)
  return prompt .. ":\n\n" .. "```" .. filetype .. "\n" .. table.concat(lines, "  ") .. "\n```\n"
end

---Write the given text to the buffer
---@param pos table
---@param bufnr number
---@param text string
---@return table
local function stream_text_to_buffer(pos, bufnr, text)
  local line = pos.line - 1
  local col = pos.col

  local index = 1
  while index <= #text do
    local newline = text:find("\n", index) or (#text + 1)
    local substring = text:sub(index, newline - 1)

    if #substring > 0 then
      api.nvim_buf_set_text(bufnr, line, col, line, col, { substring })
      col = col + #substring
    end

    if newline <= #text then
      api.nvim_buf_set_lines(bufnr, line + 1, line + 1, false, { "" })
      line = line + 1
      col = 0
    end

    index = newline + 1
  end

  pos.line = line + 1
  pos.col = col

  return pos
end

---Overwrite the given selection in the buffer with an empty string
---@param context table
local function overwrite_selection(context)
  log:trace("Overwriting selection: %s", context)
  if context.start_col > 0 then
    context.start_col = context.start_col - 1
  end

  api.nvim_buf_set_text(
    context.bufnr,
    context.start_line - 1,
    context.start_col,
    context.end_line - 1,
    context.end_col,
    { "" }
  )
  api.nvim_win_set_cursor(context.winnr, { context.start_line, context.start_col })
end

---A user's inline prompt may need to be converted into a chat
---@param inline CodeCompanion.Inline
---@param prompt table
---@return CodeCompanion.Chat|nil
local function send_to_chat(inline, prompt)
  -- If we're converting an inline prompt to a chat, we need to perform some
  -- additional steps. We need to remove any visual selections as the chat
  -- buffer adds this itself. We also need to order the system prompt
  for i = #prompt, 1, -1 do
    if inline.context.is_visual and (prompt[i].opts and prompt[i].opts.tag == "visual") then
      table.remove(prompt, i)
    elseif prompt[i].opts and prompt[i].opts.tag == "system_tag" then
      prompt[i].content = config.strategies.inline.prompts.inline_to_chat(inline.context)
      prompt[i].opts.visible = false
    end
  end

  return require("codecompanion.strategies.chat")
    .new({
      context = inline.context,
      adapter = inline.adapter,
      messages = prompt,
      auto_submit = true,
    })
    :conceal("buffers")
end

---@class CodeCompanion.Inline
---@field id integer
---@field adapter CodeCompanion.Adapter
---@field chat_context? table Messages from a chat buffer
---@field classification table
---@field context table
---@field current_request? table
---@field diff table
---@field opts table
---@field prompts table
local Inline = {}

---@class CodeCompanion.InlineArgs
---@field adapter? CodeCompanion.Adapter
---@field chat_context? table Messages from a chat buffer
---@field context table
---@field opts? table
---@field pre_hook? fun():number Function to run before the inline prompt is started
---@field prompts table

---@param args CodeCompanion.InlineArgs
---@return CodeCompanion.Inline|nil
function Inline.new(args)
  log:trace("Initiating Inline with args: %s", args)

  if args.opts and type(args.opts.pre_hook) == "function" then
    local bufnr = args.opts.pre_hook()

    if type(bufnr) == "number" then
      args.context.bufnr = bufnr
      args.context.start_line = 1
      args.context.start_col = 1
    end
  end

  if not args.chat_context then
    local last_chat = require("codecompanion").last_chat()
    if util.count(last_chat) > 0 then
      args.chat_context = last_chat:get_messages()
    end
  end

  local self = setmetatable({
    id = math.random(10000000),
    adapter = args.adapter or config.adapters[config.strategies.inline.adapter],
    classification = {
      placement = "",
      pos = {},
      prompts = {},
    },
    chat_context = args.chat_context or {},
    context = args.context,
    diff = {},
    opts = args.opts or {},
    prompts = vim.deepcopy(args.prompts),
  }, { __index = Inline })

  self.adapter = adapters.resolve(self.adapter)
  if not self.adapter then
    return log:error("No adapter found")
  end

  self:set_autocmds()

  log:debug("Inline instance created with ID %d", self.id)
  return self
end

---Set the autocmds for the inline prompt
---@return nil
function Inline:set_autocmds()
  local aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. self.context.bufnr, {
    clear = false,
  })

  api.nvim_create_autocmd("User", {
    group = aug,
    desc = "Listen for the classification to complete",
    pattern = "CodeCompanionRequestFinishedInlineClassify",
    callback = function(request)
      if request.data.bufnr ~= self.context.bufnr then
        return
      end
      self:classify_done()
    end,
  })

  api.nvim_create_autocmd("User", {
    group = aug,
    desc = "Listen for the submission to complete",
    pattern = "CodeCompanionRequestFinishedInlineSubmit",
    callback = function(request)
      if request.data.bufnr ~= self.context.bufnr then
        return
      end
      self:submit_done()
      api.nvim_del_augroup_by_id(aug)
    end,
  })
end

---Start the classification of the user's prompt
---@param opts? table
function Inline:start(opts)
  log:trace("Starting Inline with opts: %s", opts)

  if opts and opts[1] then
    self.opts = opts[1]
  end
  if opts and opts.args then
    return self:classify(opts.args)
  end

  if self.opts and self.opts.user_prompt then
    if type(self.opts.user_prompt) == "string" then
      return self:classify(self.opts.user_prompt)
    end

    local title
    if self.context.buftype == "terminal" then
      title = "Terminal"
    else
      title = string.gsub(self.context.filetype, "^%l", string.upper)
    end

    vim.ui.input({ prompt = title .. " Prompt" }, function(input)
      if not input then
        log:warn("No input provided")
        return
      end

      log:info("User input received: %s", input)
      return self:classify(input)
    end)
  else
    return self:classify()
  end
end

---Stop the current request
---@return nil
function Inline:stop()
  if self.current_request then
    self.current_request:shutdown()
    self.current_request = nil
  end
end

---Initially, we ask the LLM to classify the prompt, with the outcome being
---a judgement on the placement of the response.
---@param user_input? string
function Inline:classify(user_input)
  self.classification.prompts = self:form_prompt()

  if user_input then
    table.insert(self.classification.prompts, {
      role = CONSTANTS.USER_ROLE,
      content = "<question>" .. user_input .. "</question>",
      opts = {
        tag = "user_prompt",
        visible = true,
      },
    })
  end

  local prompt = msg_utils.merge_messages(msg_utils.pluck_messages(vim.deepcopy(self.classification.prompts), "user"))
  log:debug("Prompt to classify: %s", prompt)

  if not self.opts.placement then
    log:info("Inline classification request started")
    util.fire("InlineStarted")
    client.new({ user_args = { event = "InlineClassify" } }):stream(
      self.adapter:map_schema_to_params(),
      self.adapter:map_roles({
        {
          role = CONSTANTS.SYSTEM_ROLE,
          content = CONSTANTS.PLACEMENT_PROMPT,
        },
        {
          role = CONSTANTS.USER_ROLE,
          content = 'The prompt to assess is: "' .. prompt[1].content .. '"',
        },
      }),
      function(err, data)
        if err then
          return log:error("Error during inline classification: %s", err)
        end

        if data then
          self.classification.placement = self.classification.placement
            .. (self.adapter.args.handlers.inline_output(data) or "")
        end
      end,
      nil,
      { bufnr = self.context.bufnr }
    )
  else
    self.classification.placement = self.opts.placement
    return self:submit()
  end
end

---Function to call when the LLM has finished classifying the prompt
---@return nil
function Inline:classify_done()
  log:info('Placement: "%s"', self.classification.placement)

  local ok, parts = pcall(function()
    return self.classification.placement:match("<(.-)>")
  end)
  if not ok or parts == "error" then
    return log:error("Could not determine where to place the output from the prompt")
  end

  self.classification.placement = parts
  if self.classification.placement == "chat" then
    log:info("Sending inline prompt to the chat buffer")
    return send_to_chat(self, self.classification.prompts)
  end
  return self:submit()
end

---Submit the prompts to the LLM to process
---@return nil
function Inline:submit()
  self.classification.pos = self:place(self.classification.placement)
  log:debug("Determined position for output: %s", self.classification.pos)

  local bufnr = self.classification.pos.bufnr or self.context.bufnr

  -- Remind the LLM to respond with code only
  table.insert(self.classification.prompts, {
    role = CONSTANTS.SYSTEM_ROLE,
    content = CONSTANTS.CODE_ONLY_PROMPT,
    opts = {
      tag = "system_tag",
      visible = false,
    },
  })

  -- Add the context from the chat buffer
  if util.count(self.chat_context) > 0 then
    local messages = msg_utils.pluck_messages(self.chat_context, CONSTANTS.LLM_ROLE)

    if #messages > 0 then
      table.insert(self.classification.prompts, {
        role = CONSTANTS.USER_ROLE,
        content = "Here is the chat history from a conversation we had earlier. To answer my question, you _may_ need to use it:\n\n"
          .. messages[#messages].content,
        opts = {
          tag = "chat_context",
          visible = false,
        },
      })
    end
  end

  log:debug("Prompts to submit: %s", self.classification.prompts)
  log:info("Inline request started")

  -- Add a keymap to cancel the request
  api.nvim_buf_set_keymap(bufnr, "n", "q", "", {
    desc = "Stop the request",
    callback = function()
      log:trace("Cancelling the inline request")
      if self.current_request then
        self:stop()
      end
    end,
  })

  self.current_request = client.new({ user_args = { event = "InlineSubmit" } }):stream(
    self.adapter:map_schema_to_params(),
    self.adapter:map_roles(self.classification.prompts),
    function(err, data)
      if err then
        log:error("Error during stream: %s", err)
        return
      end

      if data then
        local content = self.adapter.args.handlers.inline_output(data, self.context)

        if content then
          vim.cmd.undojoin()
          stream_text_to_buffer(self.classification.pos, bufnr, content)
          if self.classification.placement == "new" then
            ui.buf_scroll_to_end(bufnr)
          end
        end
      end
    end,
    function()
      self.current_request = nil
      vim.schedule(function()
        util.fire("InlineFinished", { placement = self.classification.placement })
      end)
    end,
    { bufnr = bufnr }
  )
end

---Function to call when the LLM has finished processing the prompt
---@return nil
function Inline:submit_done()
  log:info("Inline request finished")
  local bufnr = self.classification.pos.bufnr or self.context.bufnr
  api.nvim_buf_del_keymap(bufnr, "n", "q")
end

---With the placement determined, we can now place the output from the inline prompt
---@param placement string
---@return table Table consisting of line, column and buffer number
function Inline:place(placement)
  local pos = { line = self.context.start_line, col = 0 }

  if placement == "replace" then
    self:diff_removed()
    overwrite_selection(self.context)
    pos.line, pos.col = api.nvim_win_get_cursor(self.context.winnr)
  elseif placement == "add" then
    api.nvim_buf_set_lines(self.context.bufnr, self.context.end_line, self.context.end_line, false, { "" })
    pos.line = self.context.end_line + 1
    pos.col = 0
  elseif placement == "new" then
    local bufnr = api.nvim_create_buf(true, false)
    api.nvim_buf_set_option(bufnr, "filetype", self.context.filetype)

    -- TODO: This is duplicated from the chat strategy
    if config.display.inline.layout == "vertical" then
      local cmd = "vsplit"
      local window_width = config.display.chat.window.width
      local width = window_width > 1 and window_width or math.floor(vim.o.columns * window_width)
      if width ~= 0 then
        cmd = width .. cmd
      end
      vim.cmd(cmd)
    elseif config.display.inline.layout == "horizontal" then
      local cmd = "split"
      local window_height = config.display.chat.window.height
      local height = window_height > 1 and window_height or math.floor(vim.o.lines * window_height)
      if height ~= 0 then
        cmd = height .. cmd
      end
      vim.cmd(cmd)
    end

    api.nvim_win_set_buf(api.nvim_get_current_win(), bufnr)
    pos.line = 1
    pos.col = 0
    pos.bufnr = bufnr
  end

  return pos
end

---When a defined prompt is sent alongside the user's input, we need to do some
---additional processing such as evaluating conditions and determining if
---the prompt contains code which can be sent to the LLM.
---@return table
function Inline:form_prompt()
  local output = {}

  for _, prompt in ipairs(self.prompts) do
    if prompt.condition then
      if not prompt.condition(self.context) then
        goto continue
      end
    end

    if not prompt.contains_code or (prompt.contains_code and config.opts.send_code) then
      if type(prompt.content) == "function" then
        prompt.content = prompt.content(self.context)
      end

      table.insert(output, {
        role = prompt.role,
        content = prompt.content,
        opts = prompt.opts or {},
      })
    end

    ::continue::
  end

  -- Add any visual selection to the prompt
  if config.opts.send_code then
    if self.context.is_visual and not self.opts.stop_context_insertion then
      log:trace("Sending visual selection")
      table.insert(output, {
        role = CONSTANTS.USER_ROLE,
        content = code_block(
          "For context, this is the code that I've selected in the buffer",
          self.context.filetype,
          self.context.lines
        ),
        opts = {
          tag = "visual",
          visible = true,
        },
      })
    end
  end

  return output
end

---Apply diff coloring to any replaced text
---@return nil
function Inline:diff_removed()
  if
    config.display.inline.diff.enabled == false
    or self.diff.removed_id == self.id
    or (#self.context.lines == 0 or not self.context.lines)
  then
    return
  end

  local ns_id = api.nvim_create_namespace("codecompanion_diff_removed_")
  api.nvim_buf_clear_namespace(self.context.bufnr, ns_id, 0, -1)

  local diff_hl_group = api.nvim_get_hl(0, { name = config.display.inline.diff.highlights.removed or "DiffDelete" })

  local virt_lines = {}
  local win_width = api.nvim_win_get_width(0)

  for i, line in ipairs(self.context.lines) do
    local virt_text = {}

    local start_col = self.context.start_col
    local row = self.context.start_line + i - 1

    -- Set the highlights for each character on the line
    local highlights = {}
    for col = start_col, #line do
      local char = line:sub(col, col)
      local current = hl.get_hl_group(self.context.bufnr, row, col)

      if not highlights[current] then
        highlights[current] = hl.combine(diff_hl_group, current)
      end

      table.insert(virt_text, { char, highlights[current] })
    end

    -- Calculate remaining width and add right padding
    local current_width = vim.fn.strdisplaywidth(line:sub(start_col))
    local remaining_width = win_width - current_width
    if remaining_width > 0 then
      table.insert(virt_text, { string.rep(" ", remaining_width), hl.combine(diff_hl_group, "Normal") })
    end

    table.insert(virt_lines, virt_text)
  end

  api.nvim_buf_set_extmark(self.context.bufnr, ns_id, self.context.start_line - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = true,
    priority = config.display.inline.diff.priority,
  })

  keymaps.set(config.strategies.inline.keymaps, self.context.bufnr, self)
  self.diff.removed_id = self.id
end

return Inline
