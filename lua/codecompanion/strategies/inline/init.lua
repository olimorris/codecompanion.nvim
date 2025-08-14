--[[
The Inline Assistant - This is where code is applied directly to a Neovim buffer
--]]

---@class CodeCompanion.Inline
---@field id integer The ID of the inline prompt
---@field adapter CodeCompanion.HTTPAdapter The adapter to use for the inline prompt
---@field aug number The ID for the autocmd group
---@field buffer_context table The context of the buffer the inline prompt was initiated from
---@field bufnr number The buffer number to apply the inline edits to
---@field chat_context? table The content from the last opened chat buffer
---@field classification CodeCompanion.Inline.Classification Where to place the generated code in Neovim
---@field current_request? table The current request that's being processed
---@field diff? table The diff provider
---@field lines table Lines in the buffer before the inline changes
---@field opts table
---@field prompts table The prompts to send to the LLM

---@class CodeCompanion.InlineArgs
---@field adapter? CodeCompanion.HTTPAdapter
---@field buffer_context? table The context of the buffer the inline prompt was initiated from
---@field chat_context? table Messages from a chat buffer
---@field diff? table The diff provider
---@field lines? table The lines in the buffer before the inline changes
---@field opts? table
---@field placement? string The placement of the code in Neovim
---@field pre_hook? fun():number Function to run before the inline prompt is started
---@field prompts? table The prompts to send to the LLM

---@class CodeCompanion.Inline.Classification
---@field placement string The placement of the code in Neovim
---@field pos {line: number, col: number, bufnr: number} The data for where the prompt should be placed

local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")
local variables = require("codecompanion.strategies.inline.variables")

local api = vim.api
local fmt = string.format

local user_role = config.constants.USER_ROLE

local CONSTANTS = {
  AUTOCMD_GROUP = "codecompanion.inline",
  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  SYSTEM_PROMPT = [[You are a knowledgeable developer working in the Neovim text editor. You write %s code on behalf of a user, directly into their active Neovim buffer.

Your task:
- Carefully follow the user's prompt (enclosed in <prompt></prompt> tags).
- Use any provided code context to inform your response.
- Output only valid JSON as specified below.

Response schema:
%s

If you cannot answer, respond with a single-sentence reason in %s, enclosed in error tags:
{
  "error": "Reason for not being able to answer the prompt"
}

Rules:
- Validate all code carefully.
- Adhere strictly to the JSON schema.
- Do not include markdown, code fences, or explanations.
- Use proper indentation and preserve whitespace.
- Include comments if appropriate for the language.
- Do not output anything except the JSON response]],

  RESPONSE_WITHOUT_PLACEMENT = [[Return your code in valid JSON matching this schema:

{
  "type": "object",
  "required": ["code", "language"],
  "properties": {
    "code": { "type": "string" },
    "language": { "type": "string" }
  },
  "additionalProperties": false
}

Example:
{
  "code": "print('Hello World')",
  "language": "python"
}
]],

  RESPONSE_WITH_PLACEMENT = [[Return your code and placement in valid JSON matching this schema:

{
  "type": "object",
  "required": ["placement"],
  "properties": {
    "code": { "type": "string" },
    "language": { "type": "string" },
    "placement": {
      "type": "string",
      "enum": ["replace", "add", "before", "new", "chat"],
      "description": "Where to place the code in Neovim."
    }
  },
  "additionalProperties": false
}

Placement options:
- "replace": Replace the user's current visual selection in the buffer with your code.
- "add": Insert your code after the user's current cursor position in the buffer.
- "before": Insert your code before the user's current cursor position in the buffer.
- "new": Create a new Neovim buffer and insert your code there.
- "chat": The prompt is conversational, informational, or otherwise not suitable for direct code insertion; respond as a message in the chat buffer instead.

Example:

{
  "code": "print('Hello World')",
  "language": "python",
  "placement": "replace"
}

If placement is "chat", omit the "code" and "language" fields:

{
  "placement": "chat"
}]],
}

---Format code into a code block alongside a message
---@param message string
---@param filetype string
---@param code table
---@return string
local function code_block(message, filetype, code)
  return fmt(
    [[%s
<code>
```%s
%s
```
</code>]],
    message,
    filetype,
    table.concat(code, "\n")
  )
end

---Overwrite the given selection in the buffer with an empty string
---@param context table The buffer context in the inline class
local function overwrite_selection(context)
  log:trace("[Inline] Overwriting selection: %s", context)
  if context.start_col > 0 then
    context.start_col = context.start_col - 1
  end

  local line_length = #vim.api.nvim_buf_get_lines(context.bufnr, context.end_line - 1, context.end_line, true)[1]
  if context.end_col > line_length then
    context.end_col = line_length
  end

  -- NOTE: Ensure that focus is set to the correct buffer in case the user has navigated away
  api.nvim_set_current_buf(context.bufnr)
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
  log:trace("[Inline] Initiating with args: %s", args)

  local id = math.random(10000000)

  local self = setmetatable({
    id = id,
    aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. id, {
      clear = false,
    }),
    buffer_context = args.buffer_context,
    bufnr = args.buffer_context.bufnr,
    classification = {
      placement = args and args.placement,
      pos = {},
    },
    chat_context = args.chat_context or {},
    diff = args.diff or {},
    lines = {},
    opts = args.opts or {},
    prompts = vim.deepcopy(args.prompts),
  }, { __index = Inline })

  self:set_adapter(args.adapter or config.strategies.inline.adapter)
  if not self.adapter then
    return log:error("[Inline] No adapter found")
  end

  -- Check if the user has manually overridden the adapter
  if vim.g.codecompanion_adapter and self.adapter.name ~= vim.g.codecompanion_adapter then
    self:set_adapter(config.adapters[vim.g.codecompanion_adapter])
  end

  if self.opts and self.opts.placement then
    self.classification.placement = self.opts.placement
  end

  log:debug("[Inline] Instance created with ID %d", self.id)
  return self
end

---Set the adapter for the inline prompt
---@param adapter CodeCompanion.HTTPAdapter|string|function
---@return nil
function Inline:set_adapter(adapter)
  if not self.adapter or not adapters.resolved(adapter) then
    self.adapter = adapters.resolve(adapter)
  end
end

---Parse special syntax from user prompt (adapters and maintain variables)
---@param prompt string
---@return string The cleaned prompt
function Inline:parse_special_syntax(prompt)
  -- 1. Handle adapter syntax: <adapter_name>
  local adapter_pattern = "<([%w_]+)>"
  local adapter_match = prompt:match(adapter_pattern)
  if adapter_match and config.adapters[adapter_match] then
    self:set_adapter(config.adapters[adapter_match])
    prompt = prompt:gsub(adapter_pattern, "", 1) -- Remove only the first occurrence
  end

  -- 2. Handle legacy first-word adapter detection for backward compatibility
  if not adapter_match then
    local split = vim.split(prompt, " ")
    local first_word = split[1]
    if config.adapters[first_word] then
      self:set_adapter(config.adapters[first_word])
      table.remove(split, 1)
      prompt = table.concat(split, " ")
    end
  end

  return vim.trim(prompt)
end

---Prompt the LLM
---@param user_prompt? string The prompt supplied by the user
---@return nil
function Inline:prompt(user_prompt)
  log:trace("[Inline] Starting")
  log:debug("[Inline] User prompt: %s", user_prompt)

  local prompts = {}

  local function add_prompt(content, role, opts)
    table.insert(prompts, {
      content = content,
      role = role or user_role,
      opts = opts or { visible = true },
    })
  end

  -- Add system prompt first
  table.insert(prompts, {
    role = config.constants.SYSTEM_ROLE,
    content = fmt(
      CONSTANTS.SYSTEM_PROMPT,
      self.buffer_context.filetype,
      (self.classification.placement and CONSTANTS.RESPONSE_WITHOUT_PLACEMENT or CONSTANTS.RESPONSE_WITH_PLACEMENT),
      config.opts.language
    ),
    opts = {
      tag = "system_tag",
      visible = false,
    },
  })

  -- Followed by prompts from external sources
  local ext_prompts = self:make_ext_prompts()
  if ext_prompts then
    for i = 1, #ext_prompts do
      prompts[#prompts + 1] = ext_prompts[i]
    end
  end

  if user_prompt then
    -- Parse adapters and variables from the entire prompt
    user_prompt = self:parse_special_syntax(user_prompt)

    -- Check for any variables
    local vars = variables.new({ inline = self, prompt = user_prompt })
    local found = vars:find():replace():output()
    if found then
      for _, var in ipairs(found) do
        add_prompt(var, user_role, { visible = false })
      end
      user_prompt = vars.prompt
    end

    -- Add the user's prompt
    add_prompt("<prompt>" .. user_prompt .. "</prompt>")
    log:debug("[Inline] Modified user prompt: %s", user_prompt)
  end

  -- From the prompt library, user's can explicitly ask to be prompted for input
  if self.opts and self.opts.user_prompt then
    local title = string.gsub(self.buffer_context.filetype, "^%l", string.upper)
    vim.schedule(function()
      vim.ui.input({ prompt = title .. " " .. config.display.action_palette.prompt }, function(input)
        if not input then
          return
        end

        log:info("[Inline] User input received: %s", input)
        add_prompt("<prompt>" .. input .. "</prompt>", user_role)
        self.prompts = prompts
        return self:submit(vim.deepcopy(prompts))
      end)
    end)
  else
    self.prompts = prompts
    return self:submit(vim.deepcopy(prompts))
  end
end

---Prompts can enter the inline class from numerous external sources such as the
---cmd line and the action palette. We begin to form the payload to send to
---the LLM in this method, checking conditions and expanding functions.
---@return table|nil
function Inline:make_ext_prompts()
  local prompts = {}

  if self.prompts then
    for _, prompt in ipairs(self.prompts) do
      if prompt.opts and prompt.opts.contains_code and not config.can_send_code() then
        goto continue
      end
      if prompt.condition and not prompt.condition(self.buffer_context) then
        goto continue
      end
      if type(prompt.content) == "function" then
        prompt.content = prompt.content(self.buffer_context)
      end
      table.insert(prompts, {
        role = prompt.role,
        content = prompt.content,
        opts = prompt.opts or {},
      })
      ::continue::
    end
  end

  -- Add any visual selections to the prompt
  if config.can_send_code() then
    if self.buffer_context.is_visual and not self.opts.stop_context_insertion then
      log:trace("[Inline] Sending visual selection")
      table.insert(prompts, {
        role = user_role,
        content = code_block(
          "For context, this is the code that I've visually selected in the buffer, which is relevant to my prompt:",
          self.buffer_context.filetype,
          self.buffer_context.lines
        ),
        opts = {
          tag = "visual",
          visible = false,
        },
      })
    end
  end

  return prompts
end

---Stop the current request
---@return nil
function Inline:stop()
  if self.current_request then
    self.current_request:shutdown()
    self.current_request = nil
    self.adapter.handlers.on_exit(self.adapter)
  end
end

local _streaming = true

---Submit the prompts to the LLM to process
---@param prompt table The prompts to send to the LLM
---@return nil
function Inline:submit(prompt)
  log:info("[Inline] Request started")

  -- Inline editing only works with streaming off - We should remember the current status
  _streaming = self.adapter.opts.stream
  self.adapter.opts.stream = false

  -- Set keymaps and start diffing
  self:setup_buffer()

  self.current_request = client
    .new({ adapter = self.adapter:map_schema_to_params(), user_args = { event = "InlineStarted" } })
    :request({ messages = self.adapter:map_roles(prompt) }, {
      ---@param err string
      ---@param data table
      ---@param adapter CodeCompanion.HTTPAdapter The modified adapter from the http client
      callback = function(err, data, adapter)
        local function error(msg)
          log:error("[Inline] Request failed with error %s", msg)
        end

        if err then
          return error(err)
        end

        if data then
          data = self.adapter.handlers.inline_output(adapter, data, self.buffer_context)
          if data.status == CONSTANTS.STATUS_SUCCESS then
            return self:done(data.output)
          else
            return error(data.output)
          end
        end
      end,
    }, {
      bufnr = self.bufnr,
      buffer_context = self.buffer_context or {},
      strategy = "inline",
    })
end

---Once the request has been completed, we can process the output
---@param output string The output from the LLM
---@return nil
function Inline:done(output)
  util.fire("InlineFinished")
  log:info("[Inline] Request finished")

  local adapter_name = self.adapter.formatted_name

  if not output then
    log:error("[%s] No output received", adapter_name)
    return self:reset()
  end

  local json = self:parse_output(output)
  if not json then
    -- Logging is done in parse_output
    return self:reset()
  end
  if json and json.error then
    log:error("[%s] %s", adapter_name, json.error)
    return self:reset()
  end

  -- There should always be a placement whether that's from the LLM or the user's prompt
  local placement = json and json.placement or self.classification.placement
  if not placement then
    log:error("[%s] No placement returned", adapter_name)
    return self:reset()
  end
  placement = string.lower(placement)

  log:debug("[Inline] Placement: %s", placement)

  -- An LLM won't send code if it deems the placement should go to a chat buffer
  if json and not json.code and placement ~= "chat" then
    log:error("[%s] Returned no code", adapter_name)
    return self:reset()
  end

  if placement == "chat" then
    self:reset()
    return self:to_chat()
  end
  self:place(placement)

  vim.schedule(function()
    self:start_diff()
    pcall(vim.cmd.undojoin)
    self:output(json.code)
    self:reset()
  end)
end

---Setup the buffer prior to sending the request to the LLM
---@return nil
function Inline:setup_buffer()
  -- Add a keymap to cancel the request
  api.nvim_buf_set_keymap(self.buffer_context.bufnr, "n", "q", "", {
    desc = "Stop the request",
    callback = function()
      log:trace("[Inline] Cancelling the request")
      if self.current_request then
        self:stop()
      end
    end,
  })
end

---Reset the inline prompt class
---@return nil
function Inline:reset()
  self.adapter.opts.stream = _streaming
  self.current_request = nil
  api.nvim_buf_del_keymap(self.bufnr, "n", "q")
  api.nvim_clear_autocmds({ group = self.aug })
end

---Extract a code block from markdown text
---@param content string
---@return string|nil
local function parse_with_treesitter(content)
  log:debug("[Inline] Parsing markdown content with Tree-sitter")

  local parser = vim.treesitter.get_string_parser(content, "markdown")
  local syntax_tree = parser:parse()
  local root = syntax_tree[1]:root()

  local query = vim.treesitter.query.parse("markdown", [[(code_fence_content) @code]])

  local code = {}
  for id, node in query:iter_captures(root, content, 0, -1) do
    if query.captures[id] == "code" then
      local node_text = vim.treesitter.get_node_text(node, content)
      -- Deepseek protection!!
      node_text = node_text:gsub("```json", "")
      node_text = node_text:gsub("```", "")

      table.insert(code, node_text)
    end
  end

  return vim.tbl_count(code) > 0 and table.concat(code, "") or nil
end

---@param output string
---@return table|nil
function Inline:parse_output(output)
  -- Try parsing as plain JSON first
  output = output:gsub("^```json", ""):gsub("```$", "")
  local _, json = pcall(vim.json.decode, output)
  if json then
    log:debug("[Inline] Parsed json:\n%s", json)
    return json
  end

  -- Fall back to Tree-sitter parsing
  local markdown_code = parse_with_treesitter(output)
  if markdown_code then
    _, json = pcall(vim.json.decode, markdown_code)
    if json then
      log:debug("[Inline] Parsed markdown JSON:\n%s", json)
      return json
    end
  end

  return log:error("[Inline] Failed to parse the response")
end

---Write the output from the LLM to the buffer
---@param output string
---@return nil
function Inline:output(output)
  local line = self.classification.pos.line - 1
  local col = self.classification.pos.col
  local bufnr = self.classification.pos.bufnr

  log:debug("[Inline] Writing to buffer %s (row: %s, col: %s)", bufnr, line, col)

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

---With the placement determined, we can now place the output from the inline prompt
---@param placement string
---@return CodeCompanion.Inline
function Inline:place(placement)
  local pos = { line = self.buffer_context.start_line, col = 0, bufnr = 0 }

  if placement == "replace" then
    self.lines = api.nvim_buf_get_lines(self.buffer_context.bufnr, 0, -1, true)
    overwrite_selection(self.buffer_context)
    local cursor_pos = api.nvim_win_get_cursor(self.buffer_context.winnr)
    pos.line = cursor_pos[1]
    pos.col = cursor_pos[2]
    pos.bufnr = self.buffer_context.bufnr
  elseif placement == "add" then
    self.lines = api.nvim_buf_get_lines(self.buffer_context.bufnr, 0, -1, true)
    api.nvim_buf_set_lines(
      self.buffer_context.bufnr,
      self.buffer_context.end_line,
      self.buffer_context.end_line,
      false,
      { "" }
    )
    pos.line = self.buffer_context.end_line + 1
    pos.col = 0
    pos.bufnr = self.buffer_context.bufnr
  elseif placement == "before" then
    self.lines = api.nvim_buf_get_lines(self.buffer_context.bufnr, 0, -1, true)
    api.nvim_buf_set_lines(
      self.buffer_context.bufnr,
      self.buffer_context.start_line - 1,
      self.buffer_context.start_line - 1,
      false,
      { "" }
    )
    self.buffer_context.start_line = self.buffer_context.start_line + 1
    pos.line = self.buffer_context.start_line - 1
    pos.col = math.max(0, self.buffer_context.start_col - 1)
    pos.bufnr = self.buffer_context.bufnr
  elseif placement == "new" then
    local bufnr
    if self.opts and type(self.opts.pre_hook) == "function" then
      -- This is only for prompts coming from the prompt library
      bufnr = self.opts.pre_hook()
      assert(type(bufnr) == "number", "No buffer number returned from the pre_hook function")
    else
      bufnr = api.nvim_create_buf(true, false)
      local ft = util.safe_filetype(self.buffer_context.filetype)
      util.set_option(bufnr, "filetype", ft)
    end

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

---Send a prompt to the chat if the placement is chat
---@return CodeCompanion.Chat
function Inline:to_chat()
  local prompt = self.prompts
  log:info("[Inline] Sending to chat")

  for i = #prompt, 1, -1 do
    -- Remove all of the system prompts
    if prompt[i].opts and prompt[i].opts.tag == "system_tag" then
      table.remove(prompt, i)
    end
    -- Remove any visual selections as the chat buffer adds these from the context
    if self.buffer_context.is_visual and (prompt[i].opts and prompt[i].opts.tag == "visual") then
      table.remove(prompt, i)
    end
  end

  -- Turn streaming back on
  self.adapter.opts.stream = _streaming

  return require("codecompanion.strategies.chat").new({
    adapter = self.adapter,
    auto_submit = true,
    buffer_context = self.buffer_context,
    messages = prompt,
  })
end

---Start the diff process
---@return nil
function Inline:start_diff()
  if config.display.diff.enabled == false then
    return
  end

  if self.classification.placement == "new" then
    return
  end

  keymaps
    .new({
      bufnr = self.buffer_context.bufnr,
      callbacks = require("codecompanion.strategies.inline.keymaps"),
      data = self,
      keymaps = config.strategies.inline.keymaps,
    })
    :set()

  local provider = config.display.diff.provider
  local ok, diff = pcall(require, "codecompanion.providers.diff." .. provider)
  if not ok then
    return log:error("[Inline] Diff provider not found: %s", provider)
  end

  ---@type CodeCompanion.Diff
  self.diff = diff.new({
    bufnr = self.buffer_context.bufnr,
    cursor_pos = self.buffer_context.cursor_pos,
    filetype = self.buffer_context.filetype,
    contents = self.lines,
    winnr = self.buffer_context.winnr,
  })
end

return Inline
