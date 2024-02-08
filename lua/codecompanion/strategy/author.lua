local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local api = vim.api

---@class CodeCompanion.Author
---@field settings table
---@field context table
---@field client CodeCompanion.Client
---@field opts table
---@field prompts table
local Author = {}

---@class CodeCompanion.AuthorArgs
---@field settings table
---@field context table
---@field client CodeCompanion.Client
---@field opts table
---@field prompts table

---@param opts CodeCompanion.AuthorArgs
---@return CodeCompanion.Author
function Author.new(opts)
  log:trace("Initiating Author")

  return setmetatable({
    settings = config.options.ai_settings.author,
    context = opts.context,
    client = opts.client,
    opts = opts.opts,
    prompts = vim.deepcopy(opts.prompts),
  }, { __index = Author })
end

---@param user_input string|nil
function Author:execute(user_input)
  local formatted_messages = {}

  for _, prompt in ipairs(self.prompts) do
    if not prompt.contains_code or (prompt.contains_code and config.options.send_code) then
      if type(prompt.content) == "function" then
        prompt.content = prompt.content(self.context)
      end

      table.insert(formatted_messages, {
        role = prompt.role,
        content = prompt.content,
      })
    end
  end

  -- Add the user prompt last
  if self.opts.user_input and user_input then
    table.insert(formatted_messages, {
      role = "user",
      content = user_input,
    })
  end

  if config.options.send_code and self.opts.send_visual_selection and self.context.is_visual then
    table.insert(formatted_messages, 2, {
      role = "user",
      content = "For context, this is the code I will ask you to help me with:\n"
        .. table.concat(self.context.lines, "\n"),
    })
  end

  -- Overwrite any visual selection
  if self.context.is_visual then
    api.nvim_buf_set_text(
      self.context.bufnr,
      self.context.start_line - 1,
      self.context.start_col - 1,
      self.context.end_line - 1,
      self.context.end_col,
      { "" }
    )
    api.nvim_win_set_cursor(self.context.winid, { self.context.start_line, self.context.start_col - 1 })
  end

  local cursor_pos = api.nvim_win_get_cursor(self.context.winid)
  local pos = {
    line = cursor_pos[1],
    col = cursor_pos[2],
  }

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
    api.nvim_win_set_cursor(self.context.winid, { pos.line, pos.col })
  end

  local output = {}
  self.client:stream_chat(
    vim.tbl_extend("keep", self.settings, {
      messages = formatted_messages,
    }),
    self.context.bufnr,
    function(err, chunk, done)
      if err then
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      if chunk then
        log:debug("chat chunk: %s", chunk)

        local delta = chunk.choices[1].delta
        if delta.content and not delta.role then
          if self.context.buftype == "terminal" then
            table.insert(output, delta.content)
          else
            stream_buffer_text(delta.content)
          end
        end
      end

      if done then
        if self.context.buftype == "terminal" then
          log:debug("terminal: %s", output)
          api.nvim_put({ table.concat(output, "") }, "", false, true)
        end
      end
    end
  )
end

function Author:start()
  if self.opts.user_input then
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

return Author
