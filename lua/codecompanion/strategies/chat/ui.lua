--[[
Manages the UI for the chat buffer such as opening and closing splits/windows,
parsing settings and rendering extmarks.
--]]
local config = require("codecompanion.config")
local schema = require("codecompanion.schema")
local yaml = require("codecompanion.utils.yaml")

local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils")

local api = vim.api

local CONSTANTS = {
  NS_HEADER = "CodeCompanion-headers",
  NS_INTRO = "CodeCompanion-intro_message",
  NS_TOKENS = "CodeCompanion-tokens",
  NS_VIRTUAL_TEXT = "CodeCompanion-virtual_text",

  AUTOCMD_GROUP = "codecompanion.chat.ui",
}

---@class CodeCompanion.Chat.UI
local UI = {}

---@param args CodeCompanion.Chat.UIArgs
function UI.new(args)
  local self = setmetatable({
    adapter = args.adapter,
    bufnr = args.bufnr,
    header_ns = api.nvim_create_namespace(CONSTANTS.NS_HEADER),
    id = args.id,
    roles = args.roles,
    settings = args.settings,
    tokens = args.tokens,
    winnr = args.winnr,
  }, { __index = UI })

  self.aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. self.bufnr, {
    clear = false,
  })
  api.nvim_create_autocmd("InsertEnter", {
    group = self.aug,
    buffer = self.bufnr,
    once = true,
    desc = "Clear the virtual text in the CodeCompanion chat buffer",
    callback = function()
      local ns_id = api.nvim_create_namespace(CONSTANTS.NS_VIRTUAL_TEXT)
      api.nvim_buf_clear_namespace(self.bufnr, ns_id, 0, -1)
    end,
  })

  return self
end

---Open/create the chat window
---@return CodeCompanion.Chat.UI|nil
function UI:open()
  if self:is_visible() then
    return
  end
  if config.display.chat.start_in_insert_mode then
    vim.cmd("startinsert")
  end

  local window = config.display.chat.window
  local width = window.width > 1 and window.width or math.floor(vim.o.columns * window.width)
  local height = window.height > 1 and window.height or math.floor(vim.o.lines * window.height)

  if window.layout == "float" then
    local win_opts = {
      relative = window.relative,
      width = width,
      height = height,
      row = window.row or math.floor((vim.o.lines - height) / 2),
      col = window.col or math.floor((vim.o.columns - width) / 2),
      border = window.border,
      title = "Code Companion",
      title_pos = "center",
      zindex = 45,
    }
    self.winnr = api.nvim_open_win(self.bufnr, true, win_opts)
  elseif window.layout == "vertical" then
    local position = window.position
    if position == nil or (position ~= "left" and position ~= "right") then
      position = vim.opt.splitright:get() and "right" or "left"
    end
    vim.cmd("vsplit")
    if position == "left" and vim.opt.splitright:get() then
      vim.cmd("wincmd h")
    end
    if position == "right" and not vim.opt.splitright:get() then
      vim.cmd("wincmd l")
    end
    vim.cmd("vertical resize " .. width)
    self.winnr = api.nvim_get_current_win()
    api.nvim_win_set_buf(self.winnr, self.bufnr)
  elseif window.layout == "horizontal" then
    local position = window.position
    if position == nil or (position ~= "top" and position ~= "bottom") then
      position = vim.opt.splitbelow:get() and "bottom" or "top"
    end
    vim.cmd("split")
    if position == "top" and vim.opt.splitbelow:get() then
      vim.cmd("wincmd k")
    end
    if position == "bottom" and not vim.opt.splitbelow:get() then
      vim.cmd("wincmd j")
    end
    vim.cmd("resize " .. height)
    self.winnr = api.nvim_get_current_win()
    api.nvim_win_set_buf(self.winnr, self.bufnr)
  else
    self.winnr = api.nvim_get_current_win()
    api.nvim_set_current_buf(self.bufnr)
  end

  ui.set_win_options(self.winnr, window.opts)
  vim.bo[self.bufnr].textwidth = 0
  self:follow()

  log:trace("Chat opened with ID %d", self.id)
  util.fire("ChatOpened", { bufnr = self.bufnr })
  return self
end

---Hide the chat buffer from view
---@return nil
function UI:hide()
  local layout = config.display.chat.window.layout

  if layout == "float" or layout == "vertical" or layout == "horizontal" then
    if self:is_active() then
      vim.cmd("hide")
    else
      if not self.winnr then
        self.winnr = ui.buf_get_win(self.bufnr)
      end
      api.nvim_win_hide(self.winnr)
    end
  else
    vim.cmd("buffer " .. vim.fn.bufnr("#"))
  end

  util.fire("ChatHidden", { bufnr = self.bufnr })
end

---Follow the cursor in the chat buffer
---@return nil
function UI:follow()
  if not self:is_visible() then
    return
  end

  local last_line, last_column, line_count = self:last()
  if line_count == 0 then
    return
  end

  api.nvim_win_set_cursor(self.winnr, { last_line + 1, last_column })
end

---Determine if the current chat buffer is active
---@return boolean
function UI:is_active()
  return api.nvim_get_current_buf() == self.bufnr
end

---Determine if the chat buffer is visible
---@return boolean
function UI:is_visible()
  return self.winnr and api.nvim_win_is_valid(self.winnr) and api.nvim_win_get_buf(self.winnr) == self.bufnr
end

---Get the formatted header for the chat buffer
---@param role string The role of the user
---@return string
function UI:format_header(role)
  local header = "## " .. role
  if config.display.chat.show_header_separator then
    header = string.format("%s %s", header, config.display.chat.separator)
  end

  return header
end

---Format the header in the chat buffer
---@param tbl table containing the buffer contents
---@param role string The role of the user to display in the header
---@return nil
function UI:set_header(tbl, role)
  table.insert(tbl, self:format_header(role))
  table.insert(tbl, "")
end

---Render the settings and any messages in the chat buffer
---@param context table
---@param messages table
---@param opts table
---@return self
function UI:render(context, messages, opts)
  local lines = {}

  local function spacer()
    table.insert(lines, "")
  end

  -- Prevent duplicate headers
  local last_set_role

  local function add_messages_to_buf(msgs)
    for i, msg in ipairs(msgs) do
      if msg.role ~= config.constants.SYSTEM_ROLE or (msg.opts and msg.opts.visible ~= false) then
        if i > 1 and self.last_role ~= msg.role then
          spacer()
        end

        if msg.role == config.constants.USER_ROLE and last_set_role ~= config.constants.USER_ROLE then
          self:set_header(lines, self.roles.user)
        end
        if msg.role == config.constants.LLM_ROLE and last_set_role ~= config.constants.LLM_ROLE then
          self:set_header(lines, self.roles.llm)
        end

        for _, text in ipairs(vim.split(msg.content, "\n", { plain = true, trimempty = true })) do
          table.insert(lines, text)
        end

        last_set_role = msg.role
        self.last_role = msg.role

        -- The Chat:Submit method will parse the last message and it to the messages table
        if i == #msgs then
          table.remove(msgs, i)
        end
      end
    end
  end

  if config.display.chat.show_settings then
    log:trace("Showing chat settings")
    lines = { "---" }
    local keys = schema.get_ordered_keys(self.adapter.schema)
    for _, key in ipairs(keys) do
      local setting = self.settings[key]
      if type(setting) == "function" then
        setting = setting(self.adapter)
      end

      table.insert(lines, string.format("%s: %s", key, yaml.encode(setting)))
    end
    table.insert(lines, "---")
    spacer()
  end

  if vim.tbl_isempty(messages) then
    log:trace("Setting the header for the chat buffer")
    self:set_header(lines, self.roles.user)
    spacer()
  else
    log:trace("Setting the messages in the chat buffer")
    add_messages_to_buf(messages)
  end

  -- If the user has visually selected some text, add that to the chat buffer
  if context and context.is_visual and not opts.stop_context_insertion then
    log:trace("Adding visual selection to chat buffer")
    table.insert(lines, "```" .. context.filetype)
    for _, line in ipairs(context.lines) do
      table.insert(lines, line)
    end
    table.insert(lines, "```")
  end

  self:unlock_buf()
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  self:render_headers()

  self:follow()

  return self
end

---Render the headers in the chat buffer and apply extmarks
---@return nil
function UI:render_headers()
  if not config.display.chat.show_header_separator then
    return
  end

  local separator = config.display.chat.separator
  local lines = api.nvim_buf_get_lines(self.bufnr, 0, -1, false)

  for line, content in ipairs(lines) do
    if content:match("^## " .. self.roles.user) or content:match("^## " .. self.roles.llm) then
      local col = vim.fn.strwidth(content) - vim.fn.strwidth(separator)

      api.nvim_buf_set_extmark(self.bufnr, self.header_ns, line - 1, col, {
        virt_text_win_col = col,
        virt_text = { { string.rep(separator, vim.go.columns), "CodeCompanionChatSeparator" } },
        priority = 100,
      })

      -- Set the highlight group for the header
      api.nvim_buf_set_extmark(self.bufnr, self.header_ns, line - 1, 0, {
        end_col = col + 1,
        hl_group = "CodeCompanionChatHeader",
      })
    end
  end
  log:trace("Rendering headers in the chat buffer")
end

---Set any extmarks in the chat buffer
---@param opts table
---@return CodeCompanion.Chat.UI|nil
function UI:set_extmarks(opts)
  if self.intro_message or (opts.messages and vim.tbl_count(opts.messages) > 0) then
    return self
  end

  -- Welcome message
  if not config.display.chat.start_in_insert_mode then
    local ns_intro = api.nvim_create_namespace(CONSTANTS.NS_INTRO)
    local id = api.nvim_buf_set_extmark(self.bufnr, ns_intro, api.nvim_buf_line_count(self.bufnr) - 1, 0, {
      virt_text = { { config.display.chat.intro_message, "CodeCompanionVirtualText" } },
      virt_text_pos = "eol",
    })
    api.nvim_create_autocmd("InsertEnter", {
      buffer = self.bufnr,
      callback = function()
        api.nvim_buf_del_extmark(self.bufnr, ns_intro, id)
      end,
    })
    self.intro_message = true
  end

  return self
end

---Get the last line, column and line count in the chat buffer
---@return integer, integer, integer
function UI:last()
  local line_count = api.nvim_buf_line_count(self.bufnr)

  local last_line = line_count - 1
  if last_line < 0 then
    return 0, 0, line_count
  end

  local last_line_content = api.nvim_buf_get_lines(self.bufnr, -2, -1, false)
  if not last_line_content or #last_line_content == 0 then
    return last_line, 0, line_count
  end

  local last_column = #last_line_content[1]

  return last_line, last_column, line_count
end

---Display the tokens in the chat buffer
---@param parser table
---@param start_row integer
---@return nil
function UI:display_tokens(parser, start_row)
  if config.display.chat.show_token_count and self.tokens then
    local to_display = config.display.chat.token_count
    if type(to_display) == "function" then
      local ns_id = api.nvim_create_namespace(CONSTANTS.NS_TOKENS)
      to_display = to_display(self.tokens, self.adapter)
      require("codecompanion.utils.tokens").display(to_display, ns_id, parser, start_row, self.bufnr)
    end
  end
end

---Fold code under the user's heading in the chat buffer
---@return self
function UI:fold_code()
  local query = vim.treesitter.query.parse(
    "markdown",
    [[
(section
(
 (atx_heading
  (atx_h2_marker)
  heading_content: (_) @role
)
([
  (fenced_code_block)
  (indented_code_block)
] @code (#trim! @code))
))
]]
  )

  local parser = vim.treesitter.get_parser(self.bufnr, "markdown")
  local tree = parser:parse()[1]
  vim.o.foldmethod = "manual"

  local role
  for _, matches in query:iter_matches(tree:root(), self.bufnr) do
    local match = {}
    for id, nodes in pairs(matches) do
      local node = type(nodes) == "table" and nodes[1] or nodes
      match = vim.tbl_extend("keep", match, {
        [query.captures[id]] = {
          node = node,
        },
      })
    end

    if match.role then
      role = vim.trim(vim.treesitter.get_node_text(match.role.node, self.bufnr))
      if role:match(self.roles.user) and match.code then
        local start_row, _, end_row, _ = match.code.node:range()
        if start_row < end_row then
          api.nvim_buf_call(self.bufnr, function()
            vim.cmd(string.format("%d,%dfold", start_row, end_row))
          end)
        end
      end
    end
  end

  return self
end

---Lock the chat buffer from editing
function UI:lock_buf()
  vim.bo[self.bufnr].modified = false
  vim.bo[self.bufnr].modifiable = false
end

---Unlock the chat buffer for editing
function UI:unlock_buf()
  vim.bo[self.bufnr].modified = false
  vim.bo[self.bufnr].modifiable = true
end

return UI
