--[[
Manages the UI for the chat buffer such as opening and closing splits/windows,
parsing settings and rendering extmarks.
--]]
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local schema = require("codecompanion.schema")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils")
local yaml = require("codecompanion.utils.yaml")

local api = vim.api

local CONSTANTS = {
  NS_HEADER = api.nvim_create_namespace("CodeCompanion-headers"),
  NS_TOKENS = api.nvim_create_namespace("CodeCompanion-tokens"),
  NS_VIRTUAL_TEXT = api.nvim_create_namespace("CodeCompanion-virtual_text"),

  AUTOCMD_GROUP = "codecompanion.chat.ui",
}

---Set the LLM role based on the adapter
---@param role string|function
---@param adapter table
---@return string
local function set_llm_role(role, adapter)
  if type(role) == "function" then
    return role(adapter)
  end
  return role
end

---@class CodeCompanion.Chat.UI
local UI = {}

---@param args CodeCompanion.Chat.UIArgs
function UI.new(args)
  local self = setmetatable({
    adapter = args.adapter,
    chat_bufnr = args.chat_bufnr,
    chat_id = args.chat_id,
    roles = args.roles,
    settings = args.settings,
    tokens = args.tokens,
    winnr = args.winnr,
  }, { __index = UI })

  self.aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. self.chat_bufnr, {
    clear = false,
  })
  api.nvim_create_autocmd("InsertEnter", {
    group = self.aug,
    buffer = self.chat_bufnr,
    once = true,
    desc = "Clear the virtual text in the CodeCompanion chat buffer",
    callback = function()
      api.nvim_buf_clear_namespace(self.chat_bufnr, CONSTANTS.NS_VIRTUAL_TEXT, 0, -1)
    end,
  })

  return self
end

---Open/create the chat window
---@param opts? table
---@return CodeCompanion.Chat.UI|nil
function UI:open(opts)
  opts = opts or {}

  if self:is_visible() then
    return
  end
  if config.display.chat.start_in_insert_mode then
    -- Delay entering insert mode until after Telescope picker fully closes,
    -- since Telescope resets to normal mode on close.
    vim.schedule(function()
      vim.cmd("startinsert")
    end)
  end

  local window = config.display.chat.window
  local width = math.floor(vim.o.columns * 0.45)
  if window.width ~= "auto" then
    width = window.width > 1 and window.width or math.floor(vim.o.columns * window.width)
  end
  local height = window.height > 1 and window.height or math.floor(vim.o.lines * window.height)

  if window.layout == "float" then
    local win_opts = {
      relative = window.relative,
      width = width,
      height = height,
      row = window.row or math.floor((vim.o.lines - height) / 2),
      col = window.col or math.floor((vim.o.columns - width) / 2),
      border = window.border,
      title = window.title or "CodeCompanion",
      title_pos = "center",
      zindex = 45,
    }
    self.winnr = api.nvim_open_win(self.chat_bufnr, true, win_opts)
  elseif window.layout == "vertical" then
    local position = window.position
    local full_height = window.full_height
    if position == nil or (position ~= "left" and position ~= "right") then
      position = vim.opt.splitright:get() and "right" or "left"
    end
    if full_height then
      if position == "left" then
        vim.cmd("topleft vsplit")
      else
        vim.cmd("botright vsplit")
      end
    else
      vim.cmd("vsplit")
    end
    if position == "left" and vim.opt.splitright:get() then
      vim.cmd("wincmd h")
    end
    if position == "right" and not vim.opt.splitright:get() then
      vim.cmd("wincmd l")
    end
    if window.width ~= "auto" then
      vim.cmd("vertical resize " .. width)
    end
    self.winnr = api.nvim_get_current_win()
    api.nvim_win_set_buf(self.winnr, self.chat_bufnr)
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
    api.nvim_win_set_buf(self.winnr, self.chat_bufnr)
  else
    self.winnr = api.nvim_get_current_win()
    api.nvim_set_current_buf(self.chat_bufnr)
  end

  ui.set_win_options(self.winnr, window.opts)
  vim.bo[self.chat_bufnr].textwidth = 0

  if not opts.toggled then
    self:follow()
  end

  log:trace("Chat opened with ID %d", self.chat_id)
  util.fire("ChatOpened", { bufnr = self.chat_bufnr, id = self.chat_id })

  self.tools = require("codecompanion.strategies.chat.ui.tools").new({
    chat_bufnr = self.chat_bufnr,
    winnr = self.winnr,
  })

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
        self.winnr = ui.buf_get_win(self.chat_bufnr)
      end
      api.nvim_win_hide(self.winnr)
    end
  else
    vim.cmd("buffer " .. vim.fn.bufnr("#"))
  end

  util.fire("ChatHidden", { bufnr = self.chat_bufnr, id = self.chat_id })
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
  return api.nvim_get_current_buf() == self.chat_bufnr
end

---Determine if the chat buffer is visible
---@return boolean
function UI:is_visible()
  return self.winnr and api.nvim_win_is_valid(self.winnr) and api.nvim_win_get_buf(self.winnr) == self.chat_bufnr
end

---Chat buffer is visible but not in the current tab
---@return boolean
function UI:is_visible_non_curtab()
  return self:is_visible() and api.nvim_get_current_tabpage() ~= api.nvim_win_get_tabpage(self.winnr)
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
  -- If the role is the LLM then we need to swap this out for a user func
  if type(role) == "function" then
    role = set_llm_role(role, self.adapter)
  end

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
      if (msg.role ~= config.constants.SYSTEM_ROLE) and not (msg.opts and msg.opts.visible == false) then
        -- For workflow prompts: Ensure main user role doesn't get spaced
        if i > 1 and self.last_role ~= msg.role and msg.role ~= config.constants.USER_ROLE then
          spacer()
        end

        if msg.role == config.constants.USER_ROLE and last_set_role ~= config.constants.USER_ROLE then
          if last_set_role ~= nil then
            spacer()
          end
          self:set_header(lines, self.roles.user)
        end
        if msg.role == config.constants.LLM_ROLE and last_set_role ~= config.constants.LLM_ROLE then
          self:set_header(lines, set_llm_role(self.roles.llm, self.adapter))
        end

        if msg.opts and msg.opts.tag == "tool_output" then
          table.insert(lines, "")
        end

        local trimempty = not (msg.role == "user" and msg.content == "")
        for _, text in ipairs(vim.split(msg.content or "", "\n", { plain = true, trimempty = trimempty })) do
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
    local keys = schema.get_ordered_keys(self.adapter)
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
  api.nvim_buf_set_lines(self.chat_bufnr, 0, -1, false, lines)
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
  local lines = api.nvim_buf_get_lines(self.chat_bufnr, 0, -1, false)
  local llm_role = set_llm_role(self.roles.llm, self.adapter)

  for line, content in ipairs(lines) do
    if content:match("^## " .. vim.pesc(self.roles.user)) or content:match("^## " .. vim.pesc(llm_role)) then
      local col = vim.fn.strwidth(content) - vim.fn.strwidth(separator)

      api.nvim_buf_set_extmark(self.chat_bufnr, CONSTANTS.NS_HEADER, line - 1, col, {
        virt_text_win_col = col,
        virt_text = { { string.rep(separator, vim.go.columns), "CodeCompanionChatSeparator" } },
        priority = 100,
      })

      -- Set the highlight group for the header
      api.nvim_buf_set_extmark(self.chat_bufnr, CONSTANTS.NS_HEADER, line - 1, 0, {
        end_col = col + 1,
        hl_group = "CodeCompanionChatHeader",
      })
    end
  end
  log:trace("Rendering headers in the chat buffer")
end

---Set the welcome message in the chat buffer
---@return CodeCompanion.Chat.UI|nil
function UI:set_intro_msg()
  if self.intro_message then
    return self
  end

  if not config.display.chat.start_in_insert_mode then
    local extmark_id = self:set_virtual_text(config.display.chat.intro_message, "eol")
    api.nvim_create_autocmd("InsertEnter", {
      buffer = self.chat_bufnr,
      callback = function()
        self:clear_virtual_text(extmark_id)
      end,
    })
    self.intro_message = true
  end

  return self
end

---Set virtual text in the chat buffer
---@param message string
---@param method? string "eol", "inline" etc
---@param range? table<number, number>
---@return number The id of the extmark
function UI:set_virtual_text(message, method, range)
  range = range or { api.nvim_buf_line_count(self.chat_bufnr) - 1, 0 }

  return api.nvim_buf_set_extmark(self.chat_bufnr, CONSTANTS.NS_VIRTUAL_TEXT, range[1], range[2], {
    virt_text = { { message, "CodeCompanionVirtualText" } },
    virt_text_pos = method or "eol",
  })
end

---Clear virtual text in the chat buffer
---@param extmark_id number The id of the extmark to delete
---@return nil
function UI:clear_virtual_text(extmark_id)
  api.nvim_buf_del_extmark(self.chat_bufnr, CONSTANTS.NS_VIRTUAL_TEXT, extmark_id)
end

---Get the last line, column and line count in the chat buffer
---@return integer, integer, integer
function UI:last()
  local line_count = api.nvim_buf_line_count(self.chat_bufnr)

  local last_line = line_count - 1
  if last_line < 0 then
    return 0, 0, line_count
  end

  local last_line_content = api.nvim_buf_get_lines(self.chat_bufnr, -2, -1, false)
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
      to_display = to_display(self.tokens, self.adapter)
      require("codecompanion.utils.tokens").display(to_display, CONSTANTS.NS_TOKENS, parser, start_row, self.chat_bufnr)
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

  local parser = vim.treesitter.get_parser(self.chat_bufnr, "markdown")
  local tree = parser:parse()[1]
  vim.o.foldmethod = "manual"

  local role
  for _, matches in query:iter_matches(tree:root(), self.chat_bufnr) do
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
      role = vim.trim(vim.treesitter.get_node_text(match.role.node, self.chat_bufnr))
      if role:match(self.roles.user) and match.code then
        local start_row, _, end_row, _ = match.code.node:range()
        if start_row < end_row then
          api.nvim_buf_call(self.chat_bufnr, function()
            vim.cmd(string.format("%d,%dfold", start_row, end_row))
          end)
        end
      end
    end
  end

  return self
end

---Add a line break to the chat buffer
---@return nil
function UI:add_line_break()
  local _, _, line_count = self:last()

  self:unlock_buf()
  vim.api.nvim_buf_set_lines(self.chat_bufnr, line_count, line_count, false, { "" })
  self:lock_buf()

  self:move_cursor(true)
end

---Update the cursor position in the chat buffer
---@param cursor_has_moved boolean
---@return nil
function UI:move_cursor(cursor_has_moved)
  if config.display.chat.auto_scroll then
    if cursor_has_moved and self:is_active() then
      self:follow()
    elseif not self:is_active() then
      self:follow()
    end
  end
end

---Lock the chat buffer from editing
function UI:lock_buf()
  vim.bo[self.chat_bufnr].modified = false
  vim.bo[self.chat_bufnr].modifiable = false
end

---Unlock the chat buffer for editing
function UI:unlock_buf()
  vim.bo[self.chat_bufnr].modified = false
  vim.bo[self.chat_bufnr].modifiable = true
end

return UI
