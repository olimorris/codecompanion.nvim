local adapters = require("codecompanion.adapters")
local client = require("codecompanion.client")
local config = require("codecompanion").config

local hl = require("codecompanion.utils.highlights")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.util")

local api = vim.api

local CONSTANTS = {
  AUTOCMD_GROUP = "codecompanion.inline",

  PLACEMENT_PROMPT = [[I would like you to assess a prompt which has been made from within the Neovim text editor. Based on this prompt, I require you to determine where the output from this prompt should be placed. I am calling this determination the "<method>". For example, the user may wish for the output to be placed:

1. `after` the current cursor position
2. `before` the current cursor position
3. `replace` the current selection
4. `new` in a new buffer/file
5. `chat` in a buffer which the user can then interact with

Here are some example prompts and their correct method classification ("<method>") to help you:

- "Can you create a method/function that does XYZ" would be `after`
- "Can you create XYZ method/function before the cursor" would be `before`
- "Can you refactor/fix/amend this code?" would be `replace`
- "Can you create a method/function for XYZ and put it in a new buffer?" would be `new`
- "Can you write unit tests for this code?" would be `new`
- "Why is Neovim so popular?" or "What does this code do?" would be `chat`

As a final assessment, I'd like you to determine if any code that the user has provided to you within their prompt should be returned in your response. I am calling this determination the "<return>" evaluation and it should be a boolean value.
Please respond to this prompt in the format "<method>|<return>" where "<method>" is a string and "<replace>" is a boolean value. For example `after|false` or `chat|false` or `replace|true`. Do not provide any other content in your response.]],
  CODE_ONLY_PROMPT = [[Respond with code only. DO NOT format the code in Markdown code blocks, DO NOT use backticks AND DO NOT provide any explanations.]],

  USER_ROLE = "user",
  LLM_ROLE = "llm",
  SYSTEM_ROLE = "system",
}

local user_role = config.strategies.chat.roles.user

-- When a promp has been classified, store the outcome to this table
local classified = {
  placement = "",
  pos = {},
  prompts = {},
}

---Format given lines into a code block alongside a prompt
---@param prompt string
---@param filetype string
---@param lines table
---@return string
local function code_block(prompt, filetype, lines)
  return prompt .. ":\n\n" .. "```" .. filetype .. "\n" .. table.concat(lines, "  ") .. "\n```\n"
end

---When a defined prompt is sent alongside the user's input, we need to do some
---additional processing such as evaluating conditions and determining if
---the prompt contains code which can be sent to the LLM.
---@param inline CodeCompanion.Inline
---@param user_input? string
---@return table,string
local function build_prompt(inline, user_input)
  local output = {}

  for _, prompt in ipairs(inline.prompts) do
    if prompt.condition then
      if not prompt.condition(inline.context) then
        goto continue
      end
    end

    if not prompt.contains_code or (prompt.contains_code and config.opts.send_code) then
      if type(prompt.content) == "function" then
        prompt.content = prompt.content(inline.context)
      end

      table.insert(output, {
        role = prompt.role,
        content = prompt.content,
        opts = {
          tag = prompt.tag,
        },
      })
    end

    ::continue::
  end

  -- Add the user prompt
  if user_input then
    table.insert(output, {
      role = CONSTANTS.USER_ROLE,
      content = user_input,
      opts = {
        tag = "user_prompt",
        visible = true,
      },
    })
  end

  -- Send the visual selection
  if config.opts.send_code then
    if inline.context.is_visual and not inline.opts.stop_context_insertion then
      log:trace("Sending visual selection")
      table.insert(output, {
        role = CONSTANTS.USER_ROLE,
        content = code_block(
          "For context, this is the code that I've selected in the buffer",
          inline.context.filetype,
          inline.context.lines
        ),
        opts = {
          tag = "visual",
        },
      })
    end
  end

  local user_prompts = ""
  for _, prompt in ipairs(output) do
    if prompt.role == CONSTANTS.USER_ROLE then
      user_prompts = user_prompts .. prompt.content
    end
  end

  return output, user_prompts
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

---Get the current cursor position in the window
---@param winnr number
---@return number,number line column
local function get_cursor(winnr)
  local cursor_pos = api.nvim_win_get_cursor(winnr)
  return cursor_pos[1], cursor_pos[2]
end

---Some LLMs ignore the ask to just return text in the form of "placement|return"
---@param str string
---@return string
local function extract_placement(str)
  return str:match("(%w+|%w+)")
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
---@field context table
---@field adapter CodeCompanion.Adapter
---@field current_request table
---@field opts table
---@field diff table
---@field prompts table
local Inline = {}

---@class CodeCompanion.InlineArgs
---@field context table
---@field adapter? CodeCompanion.Adapter
---@field opts? table
---@field pre_hook? fun():number -- Assuming pre_hook returns a number for example
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

  local self = setmetatable({
    id = math.random(10000000),
    context = args.context,
    adapter = args.adapter or config.adapters[config.strategies.inline.adapter],
    opts = args.opts or {},
    diff = {},
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

---@param opts? table
function Inline:start(opts)
  log:trace("Starting Inline with opts: %s", opts)

  -- Any prompt that's been classified, prior to submission, is stored in the classified table
  classified.pos = {}
  classified.prompts = {}
  classified.placement = ""

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
  log:info("User input: %s", user_input)

  local user_prompts
  classified.prompts, user_prompts = build_prompt(self, user_input)
  log:debug("Prompts: %s", classified.prompts)
  log:debug("User Prompt: %s", user_prompts)

  if not self.opts.placement then
    local action = {
      {
        role = CONSTANTS.SYSTEM_ROLE,
        content = CONSTANTS.PLACEMENT_PROMPT,
      },
      {
        role = user_role,
        content = 'The prompt to assess is: "' .. user_prompts .. '"',
      },
    }

    log:info("Inline classification request started")
    util.fire("InlineStarted")
    client
      .new({ user_args = { event = "InlineClassify" } })
      :stream(self.adapter:map_schema_to_params(), self.adapter:map_roles(action), function(err, data)
        if err then
          return log:error("Error during inline classification: %s", err)
        end

        if data then
          classified.placement = classified.placement .. (self.adapter.args.handlers.inline_output(data) or "")
        end
      end, nil, { bufnr = self.context.bufnr })
  else
    classified.placement = self.opts.placement
    classified.prompts = classified.prompts
    return self:submit()
  end
end

---Function to call when the LLM has finished classifying the prompt
---@return nil
function Inline:classify_done()
  log:info("Placement: %s", classified.placement)

  -- Work out where to place the output from the inline prompt
  local ok, parts = pcall(function()
    return vim.split(extract_placement(classified.placement), "|")
  end)
  if not ok or #parts < 2 then
    return log:error("Could not determine where to place the output from the prompt")
  end

  classified.placement = parts[1]
  if classified.placement == "chat" then
    log:info("Sending inline prompt to the chat buffer")
    return send_to_chat(self, classified.prompts)
  end
  return self:submit()
end

---Submit the prompts to the LLM to process
---@return nil
function Inline:submit()
  classified.pos = self:place(classified.placement)
  log:debug("Determined position for output: %s", classified.pos)

  local bufnr = classified.pos.bufnr or self.context.bufnr

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

  -- Remind the LLM to respond with code only
  table.insert(classified.prompts, {
    role = CONSTANTS.SYSTEM_ROLE,
    content = CONSTANTS.CODE_ONLY_PROMPT,
  })

  log:info("Inline request started")

  self.current_request = client.new({ user_args = { event = "InlineSubmit" } }):stream(
    self.adapter:map_schema_to_params(),
    self.adapter:map_roles(classified.prompts),
    function(err, data)
      if err then
        log:error("Error during stream: %s", err)
        return
      end

      if data then
        local content = self.adapter.args.handlers.inline_output(data, self.context)

        if content then
          vim.cmd.undojoin()
          stream_text_to_buffer(classified.pos, bufnr, content)
          -- self:diff_added(updated_pos.line)
          if classified.placement == "new" then
            ui.buf_scroll_to_end(bufnr)
          end
        end
      end
    end,
    function()
      self.current_request = nil
      vim.schedule(function()
        util.fire("InlineFinished", { placement = classified.placement })
      end)
    end,
    { bufnr = bufnr }
  )
end

---Function to call when the LLM has finished processing the prompt
---@return nil
function Inline:submit_done()
  log:info("Inline request finished")
  local bufnr = classified.pos.bufnr or self.context.bufnr
  api.nvim_buf_del_keymap(bufnr, "n", "q")
end

---With the placement determined, we can now place the output from the inline prompt
---@param placement string
---@return table Table consisting of line, column and buffer number
function Inline:place(placement)
  local pos = { line = self.context.start_line, col = 0 }

  if placement == "before" then
    api.nvim_buf_set_lines(self.context.bufnr, self.context.start_line - 1, self.context.start_line - 1, false, { "" })
    self.context.start_line = self.context.start_line + 1
    pos.line = self.context.start_line - 1
    pos.col = self.context.start_col - 1
  elseif placement == "after" then
    api.nvim_buf_set_lines(self.context.bufnr, self.context.end_line, self.context.end_line, false, { "" })
    pos.line = self.context.end_line + 1
    pos.col = 0
  elseif placement == "replace" then
    self:diff_removed()
    overwrite_selection(self.context)
    pos.line, pos.col = get_cursor(self.context.winnr)
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

---Apply diff coloring to any added text
---@return nil
-- function Inline:diff_added(line)
--   if config.display.inline.diff.enabled == false then
--     return
--   end
--
--   if not self.diff.added_line then
--     self.diff.added_line = {}
--   end
--
--   local ns_id = api.nvim_create_namespace("codecompanion_diff_added")
--
--   api.nvim_buf_set_extmark(self.context.bufnr, ns_id, line - 1, 0, {
--     sign_text = config.display.inline.diff.sign_text,
--     sign_hl_group = config.display.inline.diff.hl_groups.added,
--     priority = config.display.inline.diff.priority,
--   })
--
--   self.diff.added_line[line] = true
-- end

return Inline
