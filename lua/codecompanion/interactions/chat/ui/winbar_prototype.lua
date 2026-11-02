-- PROTOTYPE - delete me. Not production code.
-- Question: should the split chat be labelled by an H1 in the buffer or by a winbar?
-- Plan: four variants on a live split chat, switched with :CodeCompanionWinbarPrototype [next|prev|A|B|C|D|off]
-- Run: open a chat with display.chat.input.layout = "split", then :lua require("codecompanion.interactions.chat.ui.winbar_prototype").start()

local adapter_utils = require("codecompanion.adapters.utils")
local config = require("codecompanion.config")

local api = vim.api

local M = {}

local GROUP = api.nvim_create_augroup("codecompanion_winbar_prototype", { clear = true })
local WINBAR = "%%{%%v:lua.require'codecompanion.interactions.chat.ui.winbar_prototype'.render('%s')%%}"

local VARIANTS = {
  { key = "A", name = "H1 heading in the buffer (current)", chat = false, input = false, remove_h1 = false },
  { key = "B", name = "Chat winbar: centred title", chat = "centred", input = false, remove_h1 = true },
  { key = "C", name = "Chat winbar: title + adapter and model", chat = "status", input = false, remove_h1 = true },
  { key = "D", name = "Input winbar: label + keys, chat unlabelled", chat = false, input = true, remove_h1 = true },
}

local state = { index = 1, chat = nil, pill = nil }

local function variant()
  return VARIANTS[state.index]
end

local function title(chat)
  return chat.title or config.display.chat.input.title
end

---@param target "chat"|"input"
---@return string
function M.render(target)
  local chat = state.chat
  if not chat then
    return ""
  end

  if target == "input" then
    return "%#CodeCompanionChatHeader# Prompt%*%=%#Comment#<C-s> send  <M-j>/<M-k> scroll  <M-g> top/bottom  [[ ]] messages %*"
  end

  if variant().chat == "centred" then
    return "%=%#CodeCompanionChatHeader#" .. title(chat) .. "%*%="
  end

  local model = adapter_utils.model(chat.adapter) or ""
  return "%#CodeCompanionChatHeader# "
    .. title(chat)
    .. "%*%=%#Comment#"
    .. (chat.adapter.formatted_name or chat.adapter.name)
    .. (model ~= "" and (" · " .. model) or "")
    .. " %*"
end

local function set_winbar(winnr, value)
  if not winnr or not api.nvim_win_is_valid(winnr) then
    return
  end
  -- Stops a user's winbar plugin reacting to OptionSet and clearing it straight back
  local eventignore = vim.o.eventignore
  vim.o.eventignore = "OptionSet"
  vim.wo[winnr].winbar = value
  vim.o.eventignore = eventignore
end

local function has_h1(chat)
  return vim.startswith(api.nvim_buf_get_lines(chat.bufnr, 0, 1, false)[1] or "", "# ")
end

---Move every row the chat tracks by number, so parsing and streaming still line up after lines come and go
local function shift_rows(chat, by)
  chat.header_line = math.max(1, chat.header_line + by)
  local builder_state = chat.builder and chat.builder.state or {}
  for _, key in ipairs({ "current_section_start", "current_header_line" }) do
    if builder_state[key] then
      builder_state[key] = math.max(0, builder_state[key] + by)
    end
  end
  for _, key in ipairs({ "followed_to", "pos" }) do
    local position = chat.ui.cursor[key]
    if position then
      position[1] = math.max(1, position[1] + by)
    end
  end
end

local function remove_h1(chat)
  if not has_h1(chat) then
    return
  end
  chat.ui:unlock_buf()
  api.nvim_buf_set_lines(chat.bufnr, 0, 2, false, {})
  chat.ui:lock_buf()
  shift_rows(chat, -2)
end

local function restore_h1(chat)
  if has_h1(chat) then
    return
  end
  chat.ui:unlock_buf()
  api.nvim_buf_set_lines(chat.bufnr, 0, 0, false, { chat.ui:format_title(), "" })
  chat.ui:lock_buf()
  shift_rows(chat, 2)
end

---Stop the chat writing the H1 back whilst a winbar variant is on
local function patch_ui(chat, remove)
  if not remove then
    chat.ui.set_title = nil
    chat.ui.render = nil
    return
  end

  local UI = getmetatable(chat.ui).__index
  chat.ui.set_title = function(ui, new_title)
    ui.title = new_title
  end
  chat.ui.render = function(ui, ...)
    local result = UI.render(ui, ...)
    remove_h1(chat)
    return result
  end
end

local function apply_h1()
  local chat = state.chat
  patch_ui(chat, variant().remove_h1)
  if variant().remove_h1 then
    remove_h1(chat)
  else
    restore_h1(chat)
  end
end

local function show_pill()
  local text = string.format(
    "  ◀  %s · %s  ▶   :CodeCompanionWinbarPrototype next|prev|A-D|off  ",
    variant().key,
    variant().name
  )
  if not state.pill or not api.nvim_win_is_valid(state.pill.winnr) then
    local bufnr = api.nvim_create_buf(false, true)
    state.pill = {
      bufnr = bufnr,
      winnr = api.nvim_open_win(bufnr, false, {
        relative = "editor",
        row = vim.o.lines - 4,
        col = 0,
        width = 1,
        height = 1,
        style = "minimal",
        border = "rounded",
        focusable = false,
        zindex = 250,
      }),
    }
    vim.wo[state.pill.winnr].winhighlight = "Normal:PmenuSel,FloatBorder:PmenuSel"
  end

  local width = vim.fn.strdisplaywidth(text)
  api.nvim_buf_set_lines(state.pill.bufnr, 0, -1, false, { text })
  api.nvim_win_set_config(state.pill.winnr, {
    relative = "editor",
    row = vim.o.lines - 5,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = 1,
  })
end

local function apply()
  local chat = state.chat
  if not chat or not chat.ui:is_visible() then
    return
  end

  set_winbar(chat.ui.winnr, variant().chat and WINBAR:format("chat") or "")
  if chat.ui.input then
    set_winbar(chat.ui.input.winnr, variant().input and WINBAR:format("input") or "")
  end
  apply_h1()
  show_pill()
end

local function switch(arg)
  if arg == "next" or arg == "" then
    state.index = state.index % #VARIANTS + 1
  elseif arg == "prev" then
    state.index = (state.index - 2) % #VARIANTS + 1
  elseif arg == "off" then
    state.index = 1
    apply()
    if state.pill then
      pcall(api.nvim_win_close, state.pill.winnr, true)
      state.pill = nil
    end
    api.nvim_clear_autocmds({ group = GROUP })
    return
  else
    for i, v in ipairs(VARIANTS) do
      if v.key == arg:upper() then
        state.index = i
      end
    end
  end
  apply()
  print(string.format("[winbar prototype] %s: %s", variant().key, variant().name))
end

function M.start()
  state.chat = require("codecompanion").buf_get_chat(0) or require("codecompanion").last_chat()
  if not state.chat or not state.chat.ui.input then
    return vim.notify("[winbar prototype] Open a chat with display.chat.input.layout = 'split' first")
  end

  api.nvim_create_user_command("CodeCompanionWinbarPrototype", function(args)
    switch(args.args)
  end, {
    nargs = "?",
    complete = function()
      return { "next", "prev", "A", "B", "C", "D", "off" }
    end,
  })

  -- Re-apply after anything that resets the winbar or rewrites the buffer, including the user's own winbar plugin
  api.nvim_clear_autocmds({ group = GROUP })
  api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "VimResized" }, {
    group = GROUP,
    callback = function()
      vim.schedule(apply)
    end,
  })
  api.nvim_create_autocmd("User", {
    group = GROUP,
    pattern = { "CodeCompanionChatCleared", "CodeCompanionChatOpened", "CodeCompanionChatDone" },
    callback = function()
      vim.schedule(apply)
    end,
  })

  state.index = 2
  apply()
end

return M
