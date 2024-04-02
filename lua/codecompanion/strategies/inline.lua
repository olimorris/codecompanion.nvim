local client = require("codecompanion.client")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local api = vim.api

---@param status string
local function fire_autocmd(status)
  vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionInline", data = { status = status } })
end

---@param filetype string
---@param lines table
---@return string
local function code_block(filetype, lines)
  return "For context, this is the code I will ask you to help me with: ```"
    .. filetype
    .. "  "
    .. table.concat(lines, "  ")
    .. "```"
end

---@param inline CodeCompanion.Inline
---@param user_input? string
---@return table
local build_prompt = function(inline, user_input)
  local output = {}

  for _, prompt in ipairs(inline.prompts) do
    if not prompt.contains_code or (prompt.contains_code and config.options.send_code) then
      if type(prompt.content) == "function" then
        prompt.content = prompt.content(inline.context)
      end

      table.insert(output, {
        role = prompt.role,
        content = prompt.content,
      })
    end
  end

  -- Add the user prompt
  if user_input then
    table.insert(output, {
      role = "user",
      content = user_input,
    })
  end

  -- Send code as context
  if config.options.send_code and inline.context.is_visual then
    table.insert(output, {
      role = "user",
      content = code_block(inline.context.filetype, inline.context.lines),
    })
  end

  return output
end

---Stream the text to the buffer
---@param pos table
---@param bufnr number
---@param text string
---@return nil
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
  api.nvim_win_set_cursor(context.winid, { context.start_line, context.start_col })
end

---Ge the curret cursor position in the window
---@param winid number
---@return number line
---@return number col
local function get_cursor(winid)
  local cursor_pos = api.nvim_win_get_cursor(winid)
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
    vim.api.nvim_buf_set_lines(
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
    vim.api.nvim_buf_set_lines(inline.context.bufnr, inline.context.end_line, inline.context.end_line, false, { "" })
    pos.line = inline.context.end_line + 1
    pos.col = 0
  elseif placement == "replace" then
    log:trace("Placing by overwriting selection")
    overwrite_selection(inline.context)
    pos.line, pos.col = get_cursor(inline.context.winid)
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

---Get the output for the inline prompt from the generative AI
---@param inline CodeCompanion.Inline
---@param placement string
---@param prompt table
---@param output table
---@return nil
local function get_inline_output(inline, placement, prompt, output)
  if not inline.adapter then
    return
  end

  -- Work out where to place the output from the inline prompt
  local parts = vim.split(placement, "|")
  local action = parts[1]

  local pos = calc_placement(inline, action)

  vim.api.nvim_buf_set_keymap(inline.context.bufnr, "n", "q", "", {
    desc = "Cancel the request",
    callback = function()
      log:trace("Cancelling the inline request")
      vim.api.nvim_exec_autocmds(
        "User",
        { pattern = "CodeCompanionRequest", data = { buf = inline.context.bufnr, action = "cancel_request" } }
      )
    end,
  })

  client.new():stream(inline.adapter:set_params(), prompt, inline.context.bufnr, function(err, data, done)
    if err then
      fire_autocmd("finished")
      return
    end

    if done then
      api.nvim_buf_del_keymap(inline.context.bufnr, "n", "q")
      if inline.context.buftype == "terminal" then
        log:debug("Terminal output: %s", output)
        api.nvim_put({ table.concat(output, "") }, "", false, true)
      end
      fire_autocmd("finished")
      return
    end

    if data then
      log:trace("Inline data: %s", data)

      local content = inline.adapter.callbacks.inline_output(data, inline.context)

      if inline.context.buftype == "terminal" then
        -- Don't stream to the terminal
        table.insert(output, content)
      else
        if content then
          stream_text_to_buffer(pos, inline.context.bufnr, content)
          if inline.opts and inline.opts.placement == "new" then
            ui.buf_scroll_to_end(inline.context.bufnr)
          end
        end
      end
    end
  end)
end

---@class CodeCompanion.Inline
---@field context table
---@field adapter CodeCompanion.Adapter
---@field opts table
---@field prompts table
local Inline = {}

---@class CodeCompanion.InlineArgs
---@field context table
---@field adapter CodeCompanion.Adapter
---@field opts table
---@field pre_hook fun():number -- Assuming pre_hook returns a number for example
---@field prompts table

---@param opts CodeCompanion.InlineArgs
---@return CodeCompanion.Inline
function Inline.new(opts)
  log:trace("Initiating Inline")

  if type(opts.pre_hook) == "function" then
    local bufnr = opts.pre_hook()

    if type(bufnr) == "number" then
      opts.context.bufnr = bufnr
      opts.context.start_line = 1
      opts.context.start_col = 1
    end
  end

  return setmetatable({
    context = opts.context,
    adapter = config.options.adapters[config.options.strategies.inline],
    opts = opts.opts or {},
    prompts = vim.deepcopy(opts.prompts),
  }, { __index = Inline })
end

---@param user_input string|nil
function Inline:execute(user_input)
  if not self.adapter then
    vim.notify("No adapter found for inline requests", vim.log.levels.ERROR)
    return
  end

  local prompt = build_prompt(self, user_input)

  if not self.opts.placement then
    local action = {
      {
        role = "system",
        content = 'I am writing a prompt from within the Neovim text editor. This prompt will go to a generative AI model which will return a response. The response will then be streamed into Neovim. However, depending on the nature of the prompt, how Neovim handles the output will vary. For instance, if the user references the words "refactor" or "update" in their prompt, they will likely want the response to replace a visual selection they\'ve made in the editor. However, if they include words such as "after" or "before", it may be insinuated that they wish the response to be placed after or before the cursor position. They may also ask for the response to be placed in a new buffer. Finally, if you they don\'t specify what they wish to do, then they likely want to stream the response into where the cursor is currently. What I\'d like you to do is analyse the following prompt and determine whether the response should be one of: 1) after 2) before 3) replace 4) new 5) cursor. We\'ll call this the "placement" and please only respond with a single word. The user may not wish for their original code to be returned back to them from the generative AI model as part of the response. An example would be if they\'ve asked the model to generate comments or documentation. However if they\'ve asked for some refactoring/modification, then the original code should be returned. Please can you determine whether the code should be returned or not by responding with a boolean flag. Can you append this to the "placement" from earlier and seperate them with a "|" character? An example would be "cursor|true". DO NOT response with anything other than "cursor|true".',
      },
      {
        role = "user",
        content = 'The prompt to analyse is: "'
          .. user_input
          .. '". Please respond with the placement and a boolean flag ONLY e.g. "cursor|true"',
      },
    }

    -- Assume the placement should be after the cursor
    vim.api.nvim_buf_set_lines(self.context.bufnr, self.context.end_line, self.context.end_line, false, { "" })

    local placement = ""
    fire_autocmd("started")
    client.new():stream(self.adapter:set_params(), action, self.context.bufnr, function(err, data, done)
      if err then
        fire_autocmd("finished")
        return
      end

      if done then
        log:trace("Placement: %s", placement)
        get_inline_output(self, placement, prompt, {})
        return
      end

      if data then
        placement = placement .. (self.adapter.callbacks.inline_output(data) or "")
      end
    end)
  else
    get_inline_output(self, self.opts.placement, prompt, {})
    return
  end
end

---@param user_input? string
function Inline:start(user_input)
  if user_input then
    return self:execute(user_input)
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

      return self:execute(input)
    end)
  else
    return self:execute()
  end
end

return Inline
