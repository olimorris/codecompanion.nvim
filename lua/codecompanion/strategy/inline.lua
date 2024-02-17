local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

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

---@param user_input string|nil
function Inline:execute(user_input)
  local messages = get_action(self, user_input)

  -- Overwrite any visual selection
  if
    (self.context.is_visual and self.opts and self.opts.placement == "replace")
    or (self.context.is_visual and not self.opts)
  then
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
  if self.opts and self.opts.placement and self.context.is_visual then
    if self.opts.placement == "before" then
      log:debug("Placing before selection: %s", self.context)
      pos.line = self.context.start_line - 1
      pos.col = self.context.start_col - 1
    elseif self.opts.placement == "after" then
      log:debug("Placing after selection: %s", self.context)
      pos.line = self.context.end_line + 1
      pos.col = 0
    elseif self.opts.placement == "new" then
      self.context.bufnr = api.nvim_create_buf(true, false)
      api.nvim_buf_set_option(self.context.bufnr, "filetype", self.context.filetype)
      api.nvim_set_current_buf(self.context.bufnr)

      pos.line = 1
      pos.col = 0
    else
      log:debug("Placing at cursor: %s", self.context)
      pos.line = self.context.start_line
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
      end
    end
  )
end

---@param input? string
function Inline:start(input)
  if input then
    return self:execute(input)
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
