--[[
The Inline Assistant - This is where code is applied directly to a Neovim buffer
--]]

---@class CodeCompanion.Inline
---@field id integer
---@field adapter CodeCompanion.Adapter
---@field aug number The ID for the autocmd group
---@field bufnr number The buffer number to apply the inline edits to
---@field chat_context? table Messages from a chat buffer
---@field classification CodeCompanion.Inline.Classification Where to place the generated code in Neovim
---@field context table
---@field current_request? table
---@field diff? table
---@field opts table
---@field prompts table

---@class CodeCompanion.InlineArgs
---@field adapter? CodeCompanion.Adapter
---@field chat_context? table Messages from a chat buffer
---@field context table The context of the buffer the inline prompt was initiated from
---@field diff? table The diff provider
---@field lines? table The lines in the buffer before the inline changes
---@field opts? table
---@field placement? string The placement of the code in Neovim
---@field pre_hook? fun():number Function to run before the inline prompt is started
---@field prompts table

---@class CodeCompanion.Inline.Classification
---@field placement string The placement of the code in Neovim
---@field pos {line: number, col: number, bufnr: number} The data for where the prompt should be placed

local TreeHandler = require("codecompanion.utils.xml.xmlhandler.tree")
local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local api = vim.api

local CONSTANTS = {
  AUTOCMD_GROUP = "codecompanion.inline",

  -- var1: language/filetype
  -- var2: response
  SYSTEM_PROMPT = [[## CONTEXT
You are a knowledgeable developer working in the Neovim text editor. You write %s code on behalf of a user.

## OBJECTIVE
You must follow the user's prompt (enclosed within <user_prompt></user_prompt> tags) to the letter, ensuring that you output high quality, fully working code. Pay attention to any code that the user has shared with you as context.

## RESPONSE
%s

### KEY CONSIDERATIONS
- **Safety and Accuracy:** Validate all code carefully.
- **CDATA Usage:** Ensure code is wrapped in CDATA blocks to protect special characters and prevent them from being misinterpreted by XML.
- **XML schema:** Follow the XML schema exactly.

### OTHER POINTS TO NOTE
- Ensure only XML is returned. No markdown, backticks, or other formatting.
- Do not include any explanations or prose.
- Use proper indentation for the target language.
- Include language-appropriate comments when needed.
- Use actual line breaks (not `\n`).
- Preserve all whitespace.]],

  RESPONSE_WITHOUT_PLACEMENT = [[Respond to the user's prompt by returning your code in XML:
```xml
<response>
  <code><![CDATA[    print('Hello World')\]\]></code>
</response>
```
This would add `    print('Hello World')` to the user's Neovim buffer.]],

  RESPONSE_WITH_PLACEMENT = [[You are required to write code and to determine the placement of the code in relation to the user's current Neovim buffer:

### PLACEMENT

Determine where to place your code in relation to the user's Neovim buffer. Your answer should be one of:
1. **Replace**: where the user's current selection in the buffer is replaced with your code.
2. **Add**: where your code is placed after the user's current cursor position in the buffer.
3. **Before**: where your code is placed before the user's current cursor position in the buffer.
4. **New**: where a new neovim buffer is created for your code.
5. **Chat**: when the placement doesn't fit in any of the above placements and/or the user's prompt is a question or a request for information.

Here are some example user prompts and how they would be placed:
- "Can you refactor/fix/amend this code?" would be **Replace** as the user is asking you to refactor their existing code.
- "Can you create a method/function that does XYZ" would be **Add** as it requires new code to be added to a buffer.
- "Can you add a docstring/comment to this function?" would be **Before** as docstrings/comments are typically before the start of a function.
- "Can you create a method/function for XYZ and put it in a new buffer?" would be **New** as the user is explicitly asking for a new Neovim buffer.
- "Can you write unit tests for this code?" would be **New** as tests are commonly written in a new Neovim buffer.
- "Why is Neovim so popular?" or "What does this code do?" would be **Chat** as the answer to this prompt would not be code.

### OUTPUT

Respond to the user's prompt by putting your code and placement in XML. For example:
```xml
<response>
  <code><![CDATA[    print('Hello World')\]\]></code>
  <placement>replace</placement>
</response>
```
This would **Replace** the user's current selection with `    print('Hello World')`.]],
}

---Format given lines into a code block alongside a prompt
---@param prompt string
---@param filetype string
---@param lines table
---@return string
local function code_block(prompt, filetype, lines)
  return prompt .. ":\n\n" .. "```" .. filetype .. "\n" .. table.concat(lines, "\n") .. "\n```\n"
end

---Overwrite the given selection in the buffer with an empty string
---@param context table
local function overwrite_selection(context)
  log:trace("Overwriting selection: %s", context)
  if context.start_col > 0 then
    context.start_col = context.start_col - 1
  end

  local line_length = #vim.api.nvim_buf_get_lines(context.bufnr, context.end_line - 1, context.end_line, true)[1]
  if context.end_col > line_length then
    context.end_col = line_length
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

---@class CodeCompanion.Inline
local Inline = {}

---@param args CodeCompanion.InlineArgs
function Inline.new(args)
  log:trace("Initiating Inline with args: %s", args)

  if args.opts and type(args.opts.pre_hook) == "function" then
    -- This is only for prompts coming from the prompt library
    local bufnr = args.opts.pre_hook()

    if type(bufnr) == "number" then
      args.context.bufnr = bufnr
      args.context.start_line = 1
      args.context.start_col = 1
    end
  end

  -- Share knowledge of the chat buffer
  if not args.chat_context then
    local last_chat = require("codecompanion").last_chat()
    if last_chat then
      args.chat_context = last_chat:get_messages()
    end
  end

  local id = math.random(10000000)

  local self = setmetatable({
    id = id,
    adapter = args.adapter or config.adapters[config.strategies.inline.adapter],
    aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. id, {
      clear = false,
    }),
    bufnr = args.context.bufnr,
    classification = {
      placement = args and args.placement,
      pos = {},
    },
    chat_context = args.chat_context or {},
    context = args.context,
    diff = args.diff or {},
    lines = {},
    opts = args.opts or {},
    prompts = vim.deepcopy(args.prompts),
  }, { __index = Inline })

  self.adapter = adapters.resolve(self.adapter)
  if not self.adapter then
    return log:error("No adapter found")
  end

  -- Check if the user has manually overridden the adapter
  if vim.g.codecompanion_adapter and self.adapter.name ~= vim.g.codecompanion_adapter then
    self.adapter = adapters.resolve(config.adapters[vim.g.codecompanion_adapter])
  end

  log:debug("Inline instance created with ID %d", self.id)
  return self
end

---Form the prompt to send to the LLM
---@param user_prompt? string
function Inline:prompt(user_prompt)
  log:trace("Starting Inline prompt")

  local response = CONSTANTS.RESPONSE_WITHOUT_PLACEMENT
  if not self.classification.placement then
    response = CONSTANTS.RESPONSE_WITH_PLACEMENT
  end

  local prompt = {
    {
      role = config.constants.SYSTEM_ROLE,
      content = string.format(CONSTANTS.SYSTEM_PROMPT, self.context.filetype, response),
      opts = {
        visible = false,
      },
    },
  }

  ---Add a prompt to the prompt table
  ---@param input string The prompt to send to the LLM
  ---@param message? string The message to send alongside the input prompt
  local function add_user_prompt(input, message)
    table.insert(prompt, {
      role = config.constants.USER_ROLE,
      content = message and (string.format(message, input)) or ("<user_prompt>" .. input .. "</user_prompt>"),
      opts = {
        visible = true,
      },
    })
  end

  -- self:form_prompt()

  -- Then add the user's prompt last
  if user_prompt then
    add_user_prompt(user_prompt)
    return self:submit(prompt)
  else
    local title = string.gsub(self.context.filetype, "^%l", string.upper)
    vim.ui.input({ prompt = title .. " " .. config.display.action_palette.prompt }, function(input)
      if not input then
        return
      end

      log:info("User input received: %s", input)
      add_user_prompt(input)
      return self:submit(prompt)
    end)
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

---Submit the prompts to the LLM to process
---@param prompt table The prompts to send to the LLM
---@return nil
function Inline:submit(prompt)
  -- Add the context from the chat buffer
  -- if not vim.tbl_isempty(self.chat_context) then
  --   local messages = adapter_utils.pluck_messages(self.chat_context, config.constants.LLM_ROLE)

  -- if #messages > 0 then
  --   table.insert(self.classification.prompts, {
  --     role = config.constants.USER_ROLE,
  --     content = "Here is the chat history from a conversation we had earlier. To answer my question, you _may_ need to use it:\n\n"
  --       .. messages[#messages].content,
  --     opts = {
  --       tag = "chat_context",
  --       visible = false,
  --     },
  --   })
  -- end
  -- end

  -- log:debug("Prompts to submit: %s", self.classification.prompts)
  log:info("Inline request started")

  -- Add a keymap to cancel the request
  api.nvim_buf_set_keymap(self.context.bufnr, "n", "q", "", {
    desc = "Stop the request",
    callback = function()
      log:trace("Cancelling the inline request")
      if self.current_request then
        self:stop()
      end
    end,
  })

  -- if vim.tbl_contains({ "replace", "add", "before" }, self.classification.placement) then
  --   self:start_diff()
  --   keymaps
  --     .new({
  --       bufnr = self.bufnr,
  --       callbacks = require("codecompanion.strategies.inline.keymaps"),
  --       data = self,
  --       keymaps = config.strategies.inline.keymaps,
  --     })
  --     :set()
  -- end

  -- Turn off streaming
  self.adapter.opts.stream = false

  self.current_request = client
    .new({ adapter = self.adapter:map_schema_to_params(), user_args = { event = "InlineStarted" } })
    :request(self.adapter:map_roles(prompt), {
      callback = function(err, data)
        if err then
          return log:error("Inline request failed with error %s", err)
        end

        if data then
          return self:done(self.adapter.handlers.inline_output(self.adapter, data, self.context))
        end
      end,
    }, {
      bufnr = self.bufnr,
      strategy = "inline",
    })
end

---Once the requset has been completed, we can process the output
---@param output string
function Inline:done(output)
  log:info("Inline request finished")
  if not output then
    return self:reset()
  end

  local code, placement = self:parse_output(output)
  if not code then
    return self:reset()
  end
  self:place(placement)

  vim.schedule(function()
    vim.cmd.undojoin()
    self:output(code)
    self:reset()
  end)
end

---Reset the inline prompt class
---@return nil
function Inline:reset()
  self.current_request = nil
  api.nvim_buf_del_keymap(self.bufnr, "n", "q")
  api.nvim_clear_autocmds({ group = self.aug })
  util.fire("InlineFinished")
end

---@param output string
---@return string,string
function Inline:parse_output(output)
  -- Try and parse the output as plain old XML
  local xml_ok, xml = pcall(function()
    local handler = TreeHandler:new()
    local parser = xml2lua.parser(handler)
    parser:parse(output)
    return handler.root.response
  end)

  if xml_ok then
    log:debug("Parsed output: %s", xml.code)
    return xml.code, string.lower(xml.placement)
  end

  -- Before resorting to using Tree-sitter
  if not xml_ok then
    --TODO: Implement this
    return output, output
  end

  return nil, nil
end

---Write the output from the LLM to the buffer
---@param output string
---@return nil
function Inline:output(output)
  local line = self.classification.pos.line - 1
  local col = self.classification.pos.col
  local bufnr = self.classification.pos.bufnr

  local lines = vim.split(output, "\n")

  -- If there's only one line, use buf_set_text
  if #lines == 1 then
    api.nvim_buf_set_text(bufnr, line, col, line, col, { output })
    self.classification.pos.line = line + 1
    self.classification.pos.col = col + #output
    return
  end

  -- For multiple lines:
  -- 1. Handle first line
  api.nvim_buf_set_text(bufnr, line, col, line, col, { lines[1] })

  -- 2. Add remaining lines
  api.nvim_buf_set_lines(bufnr, line + 1, line + 1, false, vim.list_slice(lines, 2))
end

---When a defined prompt is sent alongside the user's input, we need to do some
---additional processing such as evaluating conditions and determining if
---the prompt contains code which can be sent to the LLM.
---@return table
function Inline:form_prompt()
  local output = {}

  for _, prompt in ipairs(self.prompts) do
    if prompt.opts and prompt.opts.contains_code and not config.can_send_code() then
      goto continue
    end
    if prompt.condition and not prompt.condition(self.context) then
      goto continue
    end

    if type(prompt.content) == "function" then
      prompt.content = prompt.content(self.context)
    end

    table.insert(output, {
      role = prompt.role,
      content = prompt.content,
      opts = prompt.opts or {},
    })

    ::continue::
  end

  -- Add any visual selection to the prompt
  if config.can_send_code() then
    if self.context.is_visual and not self.opts.stop_context_insertion then
      log:trace("Sending visual selection")
      table.insert(output, {
        role = config.constants.USER_ROLE,
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

---With the placement determined, we can now place the output from the inline prompt
---@param placement string
---@return CodeCompanion.Inline
function Inline:place(placement)
  local pos = { line = self.context.start_line, col = 0, bufnr = 0 }

  if placement == "replace" then
    self.lines = api.nvim_buf_get_lines(self.context.bufnr, 0, -1, true)
    overwrite_selection(self.context)
    local cursor_pos = api.nvim_win_get_cursor(self.context.winnr)
    pos.line = cursor_pos[1]
    pos.col = cursor_pos[2]
    pos.bufnr = self.context.bufnr
  elseif placement == "add" then
    self.lines = api.nvim_buf_get_lines(self.context.bufnr, 0, -1, true)
    api.nvim_buf_set_lines(self.context.bufnr, self.context.end_line, self.context.end_line, false, { "" })
    pos.line = self.context.end_line + 1
    pos.col = 0
    pos.bufnr = self.context.bufnr
  elseif placement == "before" then
    self.lines = api.nvim_buf_get_lines(self.context.bufnr, 0, -1, true)
    api.nvim_buf_set_lines(self.context.bufnr, self.context.start_line - 1, self.context.start_line - 1, false, { "" })
    self.context.start_line = self.context.start_line + 1
    pos.line = self.context.start_line - 1
    pos.col = math.max(0, self.context.start_col - 1)
  elseif placement == "new" then
    local bufnr = api.nvim_create_buf(true, false)
    util.set_option(bufnr, "filetype", self.context.filetype)

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

  self.classification.pos = {
    line = pos.line,
    col = pos.col,
    bufnr = pos.bufnr,
  }

  return self
end

---A user's inline prompt may need to be converted into a chat
---@return CodeCompanion.Chat
function Inline:send_to_chat()
  local prompt = self.classification.prompts

  for i = #prompt, 1, -1 do
    -- Remove all of the system prompts
    if prompt[i].opts and prompt[i].opts.tag == "system_tag" then
      table.remove(prompt, i)
    end
    -- Remove any visual selections as the chat buffer adds these from the context
    if self.context.is_visual and (prompt[i].opts and prompt[i].opts.tag == "visual") then
      table.remove(prompt, i)
    end
  end

  api.nvim_clear_autocmds({ group = self.aug })

  return require("codecompanion.strategies.chat").new({
    context = self.context,
    adapter = self.adapter,
    messages = prompt,
    auto_submit = true,
  })
end

---Start the diff process
---@return nil
function Inline:start_diff()
  if config.display.diff.enabled == false then
    return
  end

  local provider = config.display.diff.provider
  local ok, diff = pcall(require, "codecompanion.providers.diff." .. provider)
  if not ok then
    return log:error("Diff provider not found: %s", provider)
  end

  ---@type CodeCompanion.Diff
  self.diff = diff.new({
    bufnr = self.context.bufnr,
    cursor_pos = self.context.cursor_pos,
    filetype = self.context.filetype,
    contents = self.lines,
    winnr = self.context.winnr,
  })
end

return Inline
