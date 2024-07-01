local client = require("codecompanion.client")
local config = require("codecompanion").config

local hl = require("codecompanion.utils.highlights")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local api = vim.api

---@param status string
local function announce(status)
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionInline", data = { status = status } })
end

---@param filetype string
---@param lines table
---@return string
local function code_block(filetype, lines)
  return "For context, this is the code I will ask you to help me with:\n\n"
    .. "```"
    .. filetype
    .. "\n"
    .. table.concat(lines, "  ")
    .. "\n```\n"
end

---@param inline CodeCompanion.Inline
---@param user_input? string
---@return table, string
local build_prompt = function(inline, user_input)
  local output = {}

  for _, prompt in ipairs(inline.prompts) do
    if not prompt.contains_code or (prompt.contains_code and config.send_code) then
      if type(prompt.content) == "function" then
        prompt.content = prompt.content(inline.context)
      end

      table.insert(output, {
        role = prompt.role,
        tag = prompt.tag,
        content = prompt.content,
      })
    end
  end

  -- Add the user prompt
  if user_input then
    table.insert(output, {
      role = "user",
      tag = "user_prompt",
      content = user_input,
    })
  end

  -- Send code as context
  if config.send_code then
    if inline.context.is_visual then
      log:trace("Sending visual selection")
      table.insert(output, {
        role = "user",
        tag = "visual",
        content = code_block(inline.context.filetype, inline.context.lines),
      })
    end
    if inline.opts.send_open_buffers then
      log:trace("Sending open buffers to the LLM")
      local buf_utils = require("codecompanion.utils.buffers")
      local buffers = buf_utils.get_open_buffers(inline.context.filetype)

      table.insert(output, {
        role = "user",
        tag = "buffers",
        content = "I've included some additional context in the form of open buffers:\n\n"
          .. buf_utils.format(buffers, inline.context.filetype),
      })
    end
  end

  local user_prompts = ""
  for _, prompt in ipairs(output) do
    if prompt.role == "user" then
      user_prompts = user_prompts .. prompt.content
    end
  end

  return output, user_prompts
end

---Stream the text to the buffer
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

---Ge the curret cursor position in the window
---@param winnr number
---@return number line
---@return number col
local function get_cursor(winnr)
  local cursor_pos = api.nvim_win_get_cursor(winnr)
  return cursor_pos[1], cursor_pos[2]
end

---Calculate the line and the column to place the output
---@param inline CodeCompanion.Inline
---@param placement string
---@return table
local function calc_placement(inline, placement)
  local pos = {}
  pos = { line = inline.context.start_line, col = 0 }

  if placement == "before" then
    log:trace("Placing before selection")
    api.nvim_buf_set_lines(
      inline.context.bufnr,
      inline.context.start_line - 1,
      inline.context.start_line - 1,
      false,
      { "" }
    )
    inline.context.start_line = inline.context.start_line + 1
    pos.line = inline.context.start_line - 1
    pos.col = inline.context.start_col - 1
  elseif placement == "after" then
    log:trace("Placing after selection")
    api.nvim_buf_set_lines(inline.context.bufnr, inline.context.end_line, inline.context.end_line, false, { "" })
    pos.line = inline.context.end_line + 1
    pos.col = 0
  elseif placement == "replace" then
    log:trace("Placing by overwriting selection")
    inline:diff_removed()
    overwrite_selection(inline.context)
    pos.line, pos.col = get_cursor(inline.context.winnr)
  elseif placement == "new" then
    log:trace("Placing in a new buffer")
    inline.context.bufnr = api.nvim_create_buf(true, false)
    api.nvim_buf_set_option(inline.context.bufnr, "filetype", inline.context.filetype)
    api.nvim_set_current_buf(inline.context.bufnr)

    pos.line = 1
    pos.col = 0
  end

  return pos
end

---Some LLMs ignore the ask to just return text in the form of "placement|return"
---@param str string
---@return string
local function extract_placement(str)
  return str:match("(%w+|%w+)")
end

---A user's prompt may need to be converted into a chat
---@param inline CodeCompanion.Inline
---@param prompt table
---@return CodeCompanion.Chat|nil
local function send_to_chat(inline, prompt)
  -- If we're converting an inline prompt to a chat, we need to perform some
  -- additional steps. We need to remove any visual selections as the chat
  -- buffer will account for this. We also need to swap the system prompt
  for i = #prompt, 1, -1 do
    if inline.context.is_visual and prompt[i].tag == "visual" then
      table.remove(prompt, i)
    elseif prompt[i].tag == "system_tag" then
      prompt[i].content = config.default_prompts.inline_to_chat(inline.context)
    end
  end

  -- Lastly, we need to re-arrange the table of prompts
  table.sort(prompt, function(a, b)
    -- System prompts come first...
    if a.role == "system" then
      return true
    end
    if b.role == "system" then
      return false
    end
    -- ...and user prompts last
    if a.tag == "user_prompt" then
      return false
    end
    if b.tag == "user_prompt" then
      return true
    end

    return false
  end)

  return require("codecompanion.strategies.chat").new({
    context = inline.context,
    adapter = inline.adapter,
    messages = prompt,
    auto_submit = true,
  })
end

---Get the output for the inline prompt from the generative AI
---@param inline CodeCompanion.Inline
---@param placement string
---@param prompt table
---@param output table
---@return nil
local function get_inline_output(inline, placement, prompt, output)
  -- Work out where to place the output from the inline prompt
  local parts = vim.split(extract_placement(placement), "|")

  if #parts < 2 then
    log:error("Could not determine where to place the output from the prompt")
    return
  end

  local action = parts[1]

  if action == "chat" then
    return send_to_chat(inline, prompt)
  end

  log:trace("Prompt: %s", prompt)

  local pos = calc_placement(inline, action)

  api.nvim_buf_set_keymap(inline.context.bufnr, "n", "q", "", {
    desc = "Stop the request",
    callback = function()
      log:trace("Cancelling the inline request")
      if inline.current_request then
        inline:stop()
      end
    end,
  })

  inline.current_request = client.new():stream(inline.adapter:set_params(), prompt, function(err, data, done)
    if err then
      return
    end

    if done then
      api.nvim_buf_del_keymap(inline.context.bufnr, "n", "q")
      if inline.context.buftype == "terminal" then
        log:debug("Terminal output: %s", output)
        api.nvim_put({ table.concat(output, "") }, "", false, true)
      end
      return
    end

    if data then
      log:trace("Inline data: %s", data)
      local content = inline.adapter.args.callbacks.inline_output(data, inline.context)

      if inline.context.buftype == "terminal" then
        -- Don't stream to the terminal
        table.insert(output, content)
      else
        if content then
          local updated_pos = stream_text_to_buffer(pos, inline.context.bufnr, content)
          -- inline:diff_added(updated_pos.line)
          if inline.opts and inline.opts.placement == "new" then
            ui.buf_scroll_to_end(inline.context.bufnr)
          end
        end
      end
    end
  end, function()
    inline.current_request = nil
    vim.schedule(function()
      announce("finished")
    end)
  end)
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
---@return CodeCompanion.Inline
function Inline.new(args)
  log:trace("Initiating Inline")

  if args.opts and type(args.opts.pre_hook) == "function" then
    local bufnr = args.opts.pre_hook()

    if type(bufnr) == "number" then
      args.context.bufnr = bufnr
      args.context.start_line = 1
      args.context.start_col = 1
    end
  end

  return setmetatable({
    id = math.random(10000000),
    context = args.context,
    adapter = config.adapters[config.strategies.inline],
    opts = args.opts or {},
    diff = {},
    prompts = vim.deepcopy(args.prompts),
  }, { __index = Inline })
end

---@param opts? table
function Inline:start(opts)
  if opts and opts[1] then
    self.opts = opts[1]
  end
  if opts and opts.args then
    return self:submit(opts.args)
  end

  if self.opts and self.opts.user_prompt then
    local title
    if self.context.buftype == "terminal" then
      title = "Terminal"
    else
      title = string.gsub(self.context.filetype, "^%l", string.upper)
    end

    vim.ui.input({ prompt = title .. " Prompt" }, function(input)
      if not input then
        return
      end

      return self:submit(input)
    end)
  else
    return self:submit()
  end
end

---Stop the current request
function Inline:stop()
  if self.current_request then
    self.current_request:shutdown()
    self.current_request = nil
  end
end

---@param user_input? string
function Inline:submit(user_input)
  if not self.adapter then
    log:error("No adapter found for Inline strategies")
    return
  end

  if type(self.adapter) == "string" then
    self.adapter = require("codecompanion.adapters").use(self.adapter)
  end

  log:trace("Inline adapter config: %s", self.adapter)

  local prompt, user_prompts = build_prompt(self, user_input)

  if not self.opts.placement then
    local action = {
      {
        role = "system",
        content = [[I would like you to assess a prompt which has been made from within the Neovim text editor. Based on this prompt, I require you to determine where the output from this prompt should be placed. I am calling this determination the "<method>". For example, the user may wish for the output to be placed:

1) `after` the current cursor position
2) `before` the current cursor position
3) `replace` the current selection
4) `new` in a new buffer/file
5) `chat` in a buffer which can be used to ask additional questions

Here are some example prompts and their correct method classification to help you:

* "Can you create a method/function that does XYZ" would be `after`
* "Can you create XYZ method/function before the cursor" would be `before`
* "Can you refactor/fix/amend this code?" would be `replace`
* "Can you create a method/function for XYZ and put it in a new buffer?" would be `new`
* "Why is Neovim so popular?" or "What does this code do?" would be `chat`

As a final assessment, I'd like you to determine if any code that the user has provided to you within their prompt should be returned in your response. I am calling this determination the "<return>" evaluation and it should be a boolean value.

Please respond to this prompt in the format "<method>|<return>" where "<method>" is a string and "<replace>" is a boolean value. For example `after|false` or `chat|false` or `replace|true`. Do not provide any addition text other than]],
      },
      {
        role = "user",
        content = 'The prompt to assess is: "' .. user_prompts,
      },
    }

    -- Assume the placement should be after the cursor
    -- api.nvim_buf_set_lines(self.context.bufnr, self.context.end_line, self.context.end_line, false, { "" })

    local placement = ""
    announce("started")
    client.new():stream(self.adapter:set_params(), action, function(err, data, done)
      if err then
        return
      end

      if done then
        log:debug("Placement: %s", placement)
        get_inline_output(self, placement, prompt, {})
        return
      end

      if data then
        placement = placement .. (self.adapter.args.callbacks.inline_output(data) or "")
      end
    end, function()
      vim.schedule(function()
        announce("finished")
      end)
    end)
  else
    get_inline_output(self, self.opts.placement, prompt, {})
    return
  end
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

  local ns_id = vim.api.nvim_create_namespace("codecompanion_diff_removed_")
  vim.api.nvim_buf_clear_namespace(self.context.bufnr, ns_id, 0, -1)

  local diff_hl_group = vim.api.nvim_get_hl(0, { name = config.display.inline.diff.hl_group or "DiffDelete" })

  local virt_lines = {}
  local win_width = vim.api.nvim_win_get_width(0)

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

  vim.api.nvim_buf_set_extmark(self.context.bufnr, ns_id, self.context.start_line - 1, 0, {
    virt_lines = virt_lines,
    virt_lines_above = true,
    priority = config.display.inline.diff.priority,
  })

  keymaps.set(config.keymaps.inline, self.context.bufnr, self)
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
--   local ns_id = vim.api.nvim_create_namespace("codecompanion_diff_added")
--
--   vim.api.nvim_buf_set_extmark(self.context.bufnr, ns_id, line - 1, 0, {
--     sign_text = config.display.inline.diff.sign_text,
--     sign_hl_group = config.display.inline.diff.hl_groups.added,
--     priority = config.display.inline.diff.priority,
--   })
--
--   self.diff.added_line[line] = true
-- end

return Inline
