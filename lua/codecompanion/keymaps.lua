local config = require("codecompanion.config")

local ts = require("codecompanion.utils.treesitter")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils.util")

local api = vim.api

local M = {}

---Clear a keymap from a specific buffer
---@param keymaps table
---@param bufnr? integer
local function clear_map(keymaps, bufnr)
  bufnr = bufnr or 0
  for _, map in pairs(keymaps) do
    for _, key in pairs(map.modes) do
      vim.keymap.del("n", key, { buffer = bufnr })
    end
  end
end

---Open a floating window with the provided lines
---@param lines table
---@param opts table
---@return nil
local function open_float(lines, opts)
  opts = opts or {}
  local window = config.display.chat.window
  local width = window.width > 1 and window.width or opts.width or 85
  local height = window.height > 1 and window.height or opts.height or 17

  local bufnr = api.nvim_create_buf(false, true)
  util.set_option(bufnr, "filetype", opts.filetype or "codecompanion")
  local winnr = api.nvim_open_win(bufnr, true, {
    relative = opts.relative or "cursor",
    border = "single",
    width = width,
    height = height,
    style = "minimal",
    row = 10,
    col = 0,
    title = opts.title or "Options",
    title_pos = "center",
  })

  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false

  if opts.opts then
    ui.set_win_options(winnr, opts.opts)
  end

  local function close()
    api.nvim_buf_delete(bufnr, { force = true })
  end

  vim.keymap.set("n", "q", close, { buffer = bufnr })
  vim.keymap.set("n", "<ESC>", close, { buffer = bufnr })
end

-- CHAT MAPPINGS --------------------------------------------------------------
local _cached_options = {}
M.options = {
  callback = function()
    if next(_cached_options) ~= nil then
      return open_float(_cached_options)
    end

    local lines = {}
    local indent = " "

    local function max(col, tbl)
      local max_length = 0
      for key, val in pairs(tbl) do
        if val.hide then
          goto continue
        end

        local get_length = (col == "key") and key or val[col]

        local length = #get_length
        if length > max_length then
          max_length = length
        end

        ::continue::
      end
      return max_length
    end

    local function pad(str, max_length, offset)
      return str .. string.rep(" ", max_length - #str + (offset or 0))
    end

    -- Workout the column spacing
    local keymaps = config.strategies.chat.keymaps
    local keymaps_max = max("description", keymaps)

    local vars = config.strategies.chat.variables
    local vars_max = max("key", vars)

    local tools = config.strategies.agent.tools
    local tools_max = max("key", tools)

    local max_length = math.max(keymaps_max, vars_max, tools_max)

    -- Keymaps
    table.insert(lines, "### Keymaps")

    for _, map in pairs(keymaps) do
      if not map.hide then
        local modes = {
          n = "Normal",
          i = "Insert",
        }

        local output = {}
        for mode, key in pairs(map.modes) do
          if type(key) == "table" then
            local keys = {}
            for _, v in ipairs(key) do
              table.insert(keys, "`" .. v .. "`")
            end
            key = table.concat(key, "|")
            table.insert(output, "`" .. key .. "` in " .. modes[mode] .. " mode")
          else
            table.insert(output, "`" .. key .. "` in " .. modes[mode] .. " mode")
          end
        end
        local output_str = table.concat(output, " and ")

        table.insert(lines, indent .. pad("_" .. map.description .. "_", max_length, 4) .. " " .. output_str)
      end
    end

    -- Variables
    table.insert(lines, "")
    table.insert(lines, "### Variables")

    for key, val in pairs(vars) do
      table.insert(lines, indent .. pad("#" .. key, max_length, 4) .. " " .. val.description)
    end

    -- Tools
    table.insert(lines, "")
    table.insert(lines, "### Tools")

    for key, val in pairs(tools) do
      if key ~= "opts" then
        table.insert(lines, indent .. pad("@" .. key, max_length, 4) .. " " .. val.description)
      end
    end

    _cached_options = lines
    open_float(lines)
  end,
}

M.send = {
  callback = function(chat)
    chat:submit()
  end,
}

M.regenerate = {
  callback = function(chat)
    chat:regenerate()
  end,
}

M.close = {
  callback = function(chat)
    chat:close()

    local chats = require("codecompanion").buf_get_chat()
    if vim.tbl_count(chats) == 0 then
      return
    end
    chats[1].chat:open()
  end,
}

M.stop = {
  callback = function(chat)
    if chat.current_request then
      chat:stop()
    end
  end,
}

M.clear = {
  callback = function(chat)
    chat:clear()
  end,
}

M.codeblock = {
  desc = "Insert a codeblock",
  callback = function(chat)
    local bufnr = api.nvim_get_current_buf()
    local cursor_pos = api.nvim_win_get_cursor(0)
    local line = cursor_pos[1]

    local ft = chat.context.filetype or ""

    local codeblock = {
      "```" .. ft,
      "",
      "```",
    }

    api.nvim_buf_set_lines(bufnr, line - 1, line, false, codeblock)
    api.nvim_win_set_cursor(0, { line + 1, vim.fn.indent(line) })
  end,
}

---@param node TSNode to yank text from
---@param register string register to yank to
local function yank_node(node, register)
  local start_row, start_col, end_row, end_col = node:range()
  local cursor_position = vim.fn.getcurpos()

  -- Create marks for the node range
  vim.api.nvim_buf_set_mark(0, "[", start_row + 1, start_col, {})
  vim.api.nvim_buf_set_mark(0, "]", end_row + 1, end_col - 1, {})

  -- Yank using marks
  vim.cmd(string.format('normal! "%s`[y`]', config.strategies.chat.opts.register))

  -- Restore position after delay
  vim.defer_fn(function()
    vim.fn.setpos(".", cursor_position)
  end, config.strategies.chat.opts.yank_jump_delay_ms)
end

M.yank_code = {
  desc = "Yank focused or the last codeblock",
  callback = function(chat)
    local node = chat:get_codeblock()
    if node ~= nil then
      yank_node(node)
    end
  end,
}

---@param chat CodeCompanion.Chat
---@param direction number
local function move_buffer(chat, direction)
  local bufs = _G.codecompanion_buffers
  local len = #bufs
  local next_buf = vim
    .iter(bufs)
    :enumerate()
    :filter(function(_, v)
      return v == chat.bufnr
    end)
    :map(function(i, _)
      return direction > 0 and bufs[(i % len) + 1] or bufs[((i - 2 + len) % len) + 1]
    end)
    :next()

  local codecompanion = require("codecompanion")

  codecompanion.buf_get_chat(chat.bufnr).ui:hide()
  codecompanion.buf_get_chat(next_buf).ui:open()
end

M.next_chat = {
  desc = "Move to the next chat",
  callback = function(chat)
    if vim.tbl_count(_G.codecompanion_buffers) == 1 then
      return
    end
    move_buffer(chat, 1)
  end,
}

M.previous_chat = {
  desc = "Move to the previous chat",
  callback = function(chat)
    if vim.tbl_count(_G.codecompanion_buffers) == 1 then
      return
    end
    move_buffer(chat, -1)
  end,
}

M.next_header = {
  desc = "Go to the next message",
  callback = function()
    ts.goto_heading("next", 1)
  end,
}

M.previous_header = {
  desc = "Go to the previous message",
  callback = function()
    ts.goto_heading("prev", 1)
  end,
}

M.change_adapter = {
  desc = "Change the adapter",
  callback = function(chat)
    if config.display.chat.show_settings then
      return
    end

    local function select_opts(prompt, conditional)
      return {
        prompt = prompt,
        kind = "codecompanion.nvim",
        format_item = function(item)
          if conditional == item then
            return "* " .. item
          end
          return "  " .. item
        end,
      }
    end

    local adapters = vim.deepcopy(config.adapters)
    local current_adapter = chat.adapter.name
    local current_model = vim.deepcopy(chat.adapter.schema.model.default)

    local adapters_list = vim
      .iter(adapters)
      :filter(function(adapter)
        return adapter ~= "opts" and adapter ~= "non_llms" and adapter ~= current_adapter
      end)
      :map(function(adapter, _)
        return adapter
      end)
      :totable()

    table.sort(adapters_list)
    table.insert(adapters_list, 1, current_adapter)

    vim.ui.select(adapters_list, select_opts("Select Adapter", current_adapter), function(selected)
      if not selected then
        return
      end

      if current_adapter ~= selected then
        chat.adapter = require("codecompanion.adapters").resolve(adapters[selected])
        util.fire("ChatAdapter", { bufnr = chat.bufnr, adapter = chat.adapter })
        chat:apply_settings()
      end

      -- Update the system prompt
      local system_prompt = config.opts.system_prompt
      if type(system_prompt) == "function" then
        if chat.messages[1].role == "system" then
          chat.messages[1].content = system_prompt(chat.adapter)
        end
      end

      -- Select a model
      local models = chat.adapter.schema.model.choices
      if type(models) == "function" then
        models = models(chat.adapter)
      end
      if not models or #models < 2 then
        return
      end

      local new_model = chat.adapter.schema.model.default
      if type(new_model) == "function" then
        new_model = new_model(chat.adapter)
      end

      models = vim
        .iter(models)
        :map(function(model, value)
          if type(model) == "string" then
            return model
          else
            return value -- This is for the table entry case
          end
        end)
        :filter(function(model)
          return model ~= new_model
        end)
        :totable()
      table.insert(models, 1, new_model)

      vim.ui.select(models, select_opts("Select Model", new_model), function(selected)
        if not selected then
          return
        end

        if current_model ~= selected then
          util.fire("ChatModel", { bufnr = chat.bufnr, model = selected })
        end

        chat:apply_model(selected)
        chat:apply_settings()
      end)
    end)
  end,
}

M.fold_code = {
  callback = function(chat)
    chat:fold_code()
  end,
}

M.debug = {
  desc = "Show debug information for the current chat",
  callback = function(chat)
    local settings, messages = chat:debug()
    if not settings and not messages then
      return
    end

    local lines = {}

    table.insert(lines, "--Settings")
    table.insert(lines, 'adapter = "' .. chat.adapter.name .. '"')

    for key, val in pairs(settings) do
      if type(val) == "number" or type(val) == "boolean" then
        table.insert(lines, key .. " = " .. val)
      elseif type(val) == "string" then
        table.insert(lines, key .. " = " .. '"' .. val .. '"')
      else
        table.insert(lines, key .. " = " .. vim.inspect(val))
      end
    end

    table.insert(lines, "")
    table.insert(lines, "--Messages")

    messages = vim.inspect(messages)
    for line in messages:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end

    open_float(lines, {
      title = "Debug Chat",
      filetype = "lua",
      relative = "editor",
      width = vim.o.columns - 5,
      height = vim.o.lines - 2,
      opts = { wrap = true },
    })
  end,
}

M.toggle_system_prompt = {
  desc = "Toggle the system prompt",
  callback = function(chat)
    chat:toggle_system_prompt()
  end,
}

-- INLINE MAPPINGS ------------------------------------------------------------

M.accept_change = {
  desc = "Accept the change from the LLM",
  callback = function(inline)
    if inline.diff then
      inline.diff:accept()
      clear_map(config.strategies.inline.keymaps, inline.diff.bufnr)
    end
  end,
}

M.reject_change = {
  desc = "Reject the change from the LLM",
  callback = function(inline)
    if inline.diff then
      inline.diff:reject()
      clear_map(config.strategies.inline.keymaps, inline.diff.bufnr)
    end
  end,
}

return M
