local client = require("codecompanion.client")
local config = require("codecompanion.config")
local adapter = config.options.adapters.inline
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

local api = vim.api

---@param status string
local function fire_autocmd(status)
  vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionInline", data = { status = status } })
end

---When a user initiates an inline request, it will be possible to infer from
---their prompt, how the output should be placed in the buffer. For instance, if
---they reference the words "refactor" or "update" in their prompt, they will
---likely want the response to replace a visual selection they've made in the
---editor. However, if they include words such as "after" or "before", it may
---be insinuated that they wish the response to be placed after or before the
---cursor. In this function, we use the power of Generative AI to determine
---the user's intent and return a placement position.
---@param inline CodeCompanion.Inline
---@param prompt string
---@return string, boolean
local function get_placement_position(inline, prompt)
  local placement = "cursor"
  local return_code = false

  local messages = {
    {
      role = "system",
      content = 'I am writing a prompt from within the Neovim text editor. This prompt will go to a GenAI model which will return a response. The response will then be streamed into Neovim. However, depending on the nature of the prompt, how Neovim handles the streaming will vary. For instance, if the user references the words "refactor" or "update" in their prompt, they will likely want the response to replace a visual selection they\'ve made in the editor. However, if they include words such as "after" or "before", it may be insinuated that they wish the response to be placed after or before the current selection. They may also ask for the response to be placed in a new buffer. Finally, if you they don\'t specify what they wish to do, then they likely want to stream the response into where the cursor is currently. What I\'d like you to do is analyse the following prompt and determine whether the response should be one of: 1) after 2) before 3) replace 4) new 5) cursor. We\'ll call this the "placement" and please only respond with a single word.',
    },
    {
      role = "system",
      content = 'The user may not wish for their original code to be returned back to them from the GenAI model as part of the response. An example would be if they\'ve asked the model to generate comments or documentation. However if they\'ve asked for some refactoring/modification, then the original code should be returned. Please can you determine whether the code should be returned or not by responding with a boolean flag. Can you append this to the "placement" from earlier and seperate them with a "|" character?',
    },
    {
      role = "user",
      content = 'The prompt to analyse is: "' .. prompt .. '"',
    },
  }

  local output
  client.new():call(adapter:set_params(), messages, function(err, data)
    if err then
      return
    end

    if data then
      print(vim.inspect(data))
    end
  end)

  log:trace("Placement output: %s", output)

  if output then
    local parts = vim.split(output, "|")
    placement = parts[1]
    return_code = parts[2] == "true"
  end

  return placement, return_code
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
local get_action = function(inline, user_input)
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

---@param context table
local function overwrite_selection(context)
  api.nvim_buf_set_text(
    context.bufnr,
    context.start_line - 1,
    context.start_col - 1,
    context.end_line - 1,
    context.end_col,
    { "" }
  )
  api.nvim_win_set_cursor(context.winid, { context.start_line, context.start_col - 1 })
end

---@param winid number
---@return number line
---@return number col
local function get_cursor(winid)
  local cursor_pos = api.nvim_win_get_cursor(winid)
  return cursor_pos[1], cursor_pos[2]
end

---@class CodeCompanion.Inline
---@field context table
---@field opts table
---@field prompts table
local Inline = {}

---@class CodeCompanion.InlineArgs
---@field context table
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
    opts = opts.opts or {},
    prompts = vim.deepcopy(opts.prompts),
  }, { __index = Inline })
end

---@param user_input string|nil
function Inline:execute(user_input)
  local pos = { line = self.context.start_line, col = 0 }

  local messages = get_action(self, user_input)

  -- if not self.opts.placement and user_input then
  --   local return_code
  --   self.opts.placement, return_code = get_placement_position(self, user_input)
  --
  --   if not return_code then
  --     table.insert(messages, {
  --       role = "user",
  --       content = "Please do not return the code I have sent in the response",
  --     })
  --   end
  --
  --   log:debug("Setting the placement to: %s", self.opts.placement)
  -- end

  -- Assume the placement should be after the cursor
  vim.api.nvim_buf_set_lines(self.context.bufnr, self.context.end_line, self.context.end_line, false, { "" })
  pos.line = self.context.end_line + 1
  pos.col = 0

  --TODO: Workout how we can re-enable this
  -- Determine where to place the response in the buffer
  -- if self.opts and self.opts.placement then
  --   if self.opts.placement == "before" then
  --     log:trace("Placing before selection")
  --     vim.api.nvim_buf_set_lines(
  --       self.context.bufnr,
  --       self.context.start_line - 1,
  --       self.context.start_line - 1,
  --       false,
  --       { "" }
  --     )
  --     self.context.start_line = self.context.start_line + 1
  --     pos.line = self.context.start_line - 1
  --     pos.col = self.context.start_col - 1
  --   elseif self.opts.placement == "after" then
  --     log:trace("Placing after selection")
  --     vim.api.nvim_buf_set_lines(self.context.bufnr, self.context.end_line, self.context.end_line, false, { "" })
  --     pos.line = self.context.end_line + 1
  --     pos.col = 0
  --   elseif self.opts.placement == "replace" then
  --     log:trace("Placing by overwriting selection")
  --     overwrite_selection(self.context)
  --
  --     pos.line, pos.col = get_cursor(self.context.winid)
  --   elseif self.opts.placement == "new" then
  --     log:trace("Placing in a new buffer")
  --     self.context.bufnr = api.nvim_create_buf(true, false)
  --     api.nvim_buf_set_option(self.context.bufnr, "filetype", self.context.filetype)
  --     api.nvim_set_current_buf(self.context.bufnr)
  --
  --     pos.line = 1
  --     pos.col = 0
  --   end
  -- end

  log:debug("Context for inline: %s", self.context)
  log:debug("Cursor position to use: %s", pos)

  local function stream_buffer_text(text)
    local line = pos.line - 1
    local col = pos.col

    local index = 1
    while index <= #text do
      local newline = text:find("\n", index) or (#text + 1)
      local substring = text:sub(index, newline - 1)

      if #substring > 0 then
        api.nvim_buf_set_text(self.context.bufnr, line, col, line, col, { substring })
        col = col + #substring
      end

      if newline <= #text then
        api.nvim_buf_set_lines(self.context.bufnr, line + 1, line + 1, false, { "" })
        line = line + 1
        col = 0
      end

      index = newline + 1
    end

    pos.line = line + 1
    pos.col = col
  end

  log:debug("Messages: %s", messages)

  vim.api.nvim_buf_set_keymap(self.context.bufnr, "n", "q", "", {
    desc = "Cancel the request",
    callback = function()
      log:trace("Cancelling the inline request")
      _G.codecompanion_jobs[self.context.bufnr].status = "stopping"
    end,
  })

  fire_autocmd("started")

  local output = {}
  client.new():stream(adapter:set_params(), messages, self.context.bufnr, function(err, data, done)
    if err then
      fire_autocmd("finished")
      return
    end

    if data then
      log:trace("Inline data: %s", data)

      local content = adapter.callbacks.inline_output(data, self.context)

      if self.context.buftype == "terminal" then
        -- Don't stream to the terminal
        table.insert(output, content)
      else
        if content then
          stream_buffer_text(content)
          if self.opts and self.opts.placement == "new" then
            ui.buf_scroll_to_end(self.context.bufnr)
          end
        end
      end
    end

    if done then
      api.nvim_buf_del_keymap(self.context.bufnr, "n", "q")
      if self.context.buftype == "terminal" then
        log:debug("Terminal output: %s", output)
        api.nvim_put({ table.concat(output, "") }, "", false, true)
      end
      fire_autocmd("finished")
    end
  end)
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
