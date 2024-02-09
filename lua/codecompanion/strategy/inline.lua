local commands = require("codecompanion.actions").static.commands
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local api = vim.api

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

---@param prompt? string
---@return table|nil
local function parse_prompt(prompt)
  if not prompt then
    return
  end

  for _, cmd in ipairs(commands) do
    if cmd.command == prompt then
      return cmd
    end
  end
end

---@param inline CodeCompanion.Inline
---@param command table
---@return table
local prompt_from_command = function(inline, command)
  local output = {}

  for _, prompt in ipairs(command.prompts) do
    if type(prompt.content) == "function" then
      prompt.content = prompt.content(inline.context)
    end

    table.insert(output, {
      role = prompt.role,
      content = prompt.content,
    })
  end

  if config.options.send_code and inline.opts.send_visual_selection and inline.context.is_visual then
    table.insert(output, {
      role = "user",
      content = code_block(inline.context.filetype, inline.context.lines),
    })
  end

  return output
end

---@param inline CodeCompanion.Inline
---@param user_prompt? string
---@return table
local prompt_from_action = function(inline, user_prompt)
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
  if inline.opts.user_prompt and user_prompt then
    table.insert(output, {
      role = "user",
      content = user_prompt,
    })
  end

  -- Send code as context
  if config.options.send_code and inline.opts.send_visual_selection and inline.context.is_visual then
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

---@class CodeCompanion.Inline
---@field settings table
---@field context table
---@field client CodeCompanion.Client
---@field opts table
---@field prompts table
local Inline = {}

---@class CodeCompanion.InlineArgs
---@field settings table
---@field context table
---@field client CodeCompanion.Client
---@field opts table
---@field prompts table

---@param opts CodeCompanion.InlineArgs
---@return CodeCompanion.Inline
function Inline.new(opts)
  log:trace("Initiating Inline")

  return setmetatable({
    settings = config.options.ai_settings.inline,
    context = opts.context,
    client = opts.client,
    opts = opts.opts,
    prompts = vim.deepcopy(opts.prompts),
  }, { __index = Inline })
end

---@param user_prompt string|nil
function Inline:execute(user_prompt)
  local command = parse_prompt(user_prompt)

  local messages = {}
  if command then
    messages = prompt_from_command(self, command)
  else
    messages = prompt_from_action(self, user_prompt)
  end

  -- Overwrite any visual selection
  if (self.context.is_visual and not command) or (command and command.opts.placement == "replace") then
    log:trace("Overwriting selection")
    overwrite_selection(self.context)
  end

  local cursor_pos = api.nvim_win_get_cursor(self.context.winid)
  local pos = {
    line = cursor_pos[1],
    col = cursor_pos[2],
  }
  log:debug("Cursor position: %s", pos)

  -- Adjust the cursor position based on the command
  if command and self.context.is_visual then
    if command.opts.placement == "before" then
      log:debug("Placing before selection: %s", self.context)
      pos.line = self.context.start_line - 1
      pos.col = self.context.start_col - 1
    elseif command.opts.placement == "after" then
      log:debug("Placing after selection: %s", self.context)
      pos.line = self.context.end_line + 1
      pos.col = 0
    elseif command.opts.placement == "new" then
      self.context.bufnr = api.nvim_create_buf(true, false)
      api.nvim_buf_set_option(self.context.bufnr, "filetype", self.context.filetype)
      api.nvim_set_current_buf(self.context.bufnr)

      pos.line = 1
      pos.col = 0
    end
  end

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

  local output = {}
  self.client:stream_chat(
    vim.tbl_extend("keep", self.settings, {
      messages = messages,
    }),
    self.context.bufnr,
    function(err, chunk, done)
      if err then
        return
      end

      if chunk then
        log:debug("chat chunk: %s", chunk)

        local delta = chunk.choices[1].delta
        if delta.content and not delta.role and delta.content ~= "```" and delta.content ~= self.context.filetype then
          if self.context.buftype == "terminal" then
            -- Don't stream to the terminal
            table.insert(output, delta.content)
          else
            stream_buffer_text(delta.content)
          end
        end
      end

      if done then
        api.nvim_buf_del_keymap(self.context.bufnr, "n", "q")
        if self.context.buftype == "terminal" then
          log:debug("Terminal output: %s", output)
          api.nvim_put({ table.concat(output, "") }, "", false, true)
        end
      end
    end
  )
end

function Inline:start()
  if self.opts.user_prompt then
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
