local client = require("codecompanion.client")
local config = require("codecompanion").config

local hl = require("codecompanion.utils.highlights")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local api = vim.api

local CONSTANTS = {
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
  CODE_ONLY_PROMPT = [[Respond with code only. Do not use any Markdown formatting for this particular answer and do not include any explanation or formatting. Code only.]],
}

local llm_role = config.strategies.chat.roles.llm
local user_role = config.strategies.chat.roles.user

---@param status string
---@param opts? table
local function announce(status, opts)
  opts = opts or {}
  opts.status = status

  api.nvim_exec_autocmds("User", { pattern = "CodeCompanionInline", data = opts })
end

---@param prompt string
---@param filetype string
---@param lines table
---@return string
local function code_block(prompt, filetype, lines)
  return prompt .. ":\n\n" .. "```" .. filetype .. "\n" .. table.concat(lines, "  ") .. "\n```\n"
end

---@param inline CodeCompanion.Inline
---@param user_input? string
---@return table, string
local build_prompt = function(inline, user_input)
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
        tag = prompt.tag,
        content = prompt.content,
      })
    end

    ::continue::
  end

  -- Add the user prompt
  if user_input then
    table.insert(output, {
      role = user_role,
      tag = "user_prompt",
      content = user_input,
    })
  end

  -- Send the visual selection
  if config.opts.send_code then
    if inline.context.is_visual then
      log:trace("Sending visual selection")
      table.insert(output, {
        role = user_role,
        tag = "visual",
        content = code_block(
          "For context, this is the code that I've selected in the buffer",
          inline.context.filetype,
          inline.context.lines
        ),
      })
    end
  end

  local user_prompts = ""
  for _, prompt in ipairs(output) do
    if prompt.role == user_role then
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
      prompt[i].content = config.strategies.inline.prompts.inline_to_chat(inline.context)
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
    adapter = config.adapters[config.strategies.inline.adapter],
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
        return
      end

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

---Initially send the prompt to the LLM to determine which type of action we
---should take in our response. At this stage we do not ask the LLM to
---generate any output, just provide a classification of the action
---@param user_input? string
function Inline:classify(user_input)
  if not self.adapter then
    log:error("No adapter found for Inline strategies")
    return
  end

  if type(self.adapter) == "string" then
    self.adapter = require("codecompanion.adapters").use(self.adapter)
  elseif type(self.adapter) == "function" then
    self.adapter = self.adapter()
  end

  log:trace("Inline adapter config: %s", self.adapter)

  local prompt, user_prompts = build_prompt(self, user_input)

  if not self.opts.placement then
    local action = {
      {
        role = "system",
        content = CONSTANTS.PLACEMENT_PROMPT,
      },
      {
        role = user_role,
        content = 'The prompt to assess is: "' .. user_prompts,
      },
    }

    local placement = ""
    announce("started")
    client.new():stream(self.adapter:set_params(), self.adapter:map_roles(action), function(err, data, done)
      if err then
        return
      end

      if done then
        log:debug("Placement: %s", placement)
        return self:submit(placement, prompt)
      end

      if data then
        placement = placement .. (self.adapter.args.callbacks.inline_output(data) or "")
      end
    end)
  else
    return self:submit(self.opts.placement, prompt)
  end
end

---Get the output for the inline prompt from the generative AI
---@param placement string
---@param prompt table
---@return nil
function Inline:submit(placement, prompt)
  -- Work out where to place the output from the inline prompt
  local parts = vim.split(extract_placement(placement), "|")

  if #parts < 2 then
    log:error("Could not determine where to place the output from the prompt")
    return
  end

  local action = parts[1]

  if action == "chat" then
    return send_to_chat(self, prompt)
  end

  log:trace("Prompt: %s", prompt)

  local pos = self:place(action)
  local bufnr = pos.bufnr or self.context.bufnr

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
  table.insert(prompt, {
    role = "system",
    content = CONSTANTS.CODE_ONLY_PROMPT,
  })

  self.current_request = client
    .new()
    :stream(self.adapter:set_params(), self.adapter:map_roles(prompt), function(err, data, done)
      if err then
        return
      end

      if done then
        return api.nvim_buf_del_keymap(bufnr, "n", "q")
      end

      if data then
        log:trace("Inline data: %s", data)
        local content = self.adapter.args.callbacks.inline_output(data, self.context)

        if content then
          stream_text_to_buffer(pos, bufnr, content)
          -- self:diff_added(updated_pos.line)
          if action == "new" then
            ui.buf_scroll_to_end(bufnr)
          end
        end
      end
    end, function()
      self.current_request = nil
      vim.schedule(function()
        announce("finished", { placement = action })
      end)
    end)
end

---Determine where to place the output from the LLM
---@param placement string
---@return table
function Inline:place(placement)
  local pos = {}
  pos = { line = self.context.start_line, col = 0 }

  if placement == "before" then
    log:trace("Placing before selection")
    api.nvim_buf_set_lines(self.context.bufnr, self.context.start_line - 1, self.context.start_line - 1, false, { "" })
    self.context.start_line = self.context.start_line + 1
    pos.line = self.context.start_line - 1
    pos.col = self.context.start_col - 1
  elseif placement == "after" then
    log:trace("Placing after selection")
    api.nvim_buf_set_lines(self.context.bufnr, self.context.end_line, self.context.end_line, false, { "" })
    pos.line = self.context.end_line + 1
    pos.col = 0
  elseif placement == "replace" then
    log:trace("Placing by overwriting selection")
    self:diff_removed()
    overwrite_selection(self.context)
    pos.line, pos.col = get_cursor(self.context.winnr)
  elseif placement == "new" then
    log:trace("Placing in a new buffer")
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
