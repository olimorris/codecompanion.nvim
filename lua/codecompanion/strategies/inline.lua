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
local build_messages = function(inline, user_input)
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

  local messages = build_messages(self, user_input)

  -- Assume the placement should be after the cursor
  vim.api.nvim_buf_set_lines(self.context.bufnr, self.context.end_line, self.context.end_line, false, { "" })
  pos.line = self.context.end_line + 1
  pos.col = 0

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

  if not adapter then
    vim.notify("No adapter found for inline requests", vim.log.levels.ERROR)
    return
  end

  client.new():stream(adapter:set_params(), messages, self.context.bufnr, function(err, data, done)
    if err then
      fire_autocmd("finished")
      return
    end

    if done then
      api.nvim_buf_del_keymap(self.context.bufnr, "n", "q")
      if self.context.buftype == "terminal" then
        log:debug("Terminal output: %s", output)
        api.nvim_put({ table.concat(output, "") }, "", false, true)
      end
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
