local async = require("plenary.async")
local completion = require("codecompanion.completion")
local config = require("codecompanion.config")
local ts = require("codecompanion.utils.treesitter")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils")

local api = vim.api

local M = {}

-- CHAT MAPPINGS --------------------------------------------------------------
local _cached_options = {}
M.options = {
  callback = function()
    local float_opts = {
      title = "Options",
      lock = true,
      window = config.display.chat.window,
    }

    if next(_cached_options) ~= nil then
      return ui.create_float(_cached_options, float_opts)
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

    local tools = config.strategies.chat.agents.tools
    local tools_max = max("key", tools)

    local max_length = math.max(keymaps_max, vars_max, tools_max)

    -- Keymaps
    table.insert(lines, "### Keymaps")

    for _, map in pairs(keymaps) do
      if type(map.condition) == "function" and not map.condition() then
        goto continue
      end
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
      ::continue::
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
    ui.create_float(lines, float_opts)
  end,
}

-- Native completion
M.completion = {
  callback = function(chat)
    local function complete_items(callback)
      async.run(function()
        local slash_cmds = completion.slash_commands()
        local tools = completion.tools()
        local vars = completion.variables()

        local items = {}

        if type(slash_cmds[1]) == "table" then
          vim.list_extend(items, slash_cmds)
        end
        if type(tools[1]) == "table" then
          vim.list_extend(items, tools)
        end
        if type(vars[1]) == "table" then
          vim.list_extend(items, vars)
        end

        -- Process each item to match the completion format
        for _, item in ipairs(items) do
          if item.label then
            item.word = item.label
            item.abbr = item.label:sub(2)
            item.menu = item.description or item.detail
            item.icase = 1
            item.dup = 0
            item.empty = 0
            item.user_data = {
              command = item.label:sub(2),
              label = item.label,
              type = item.type,
              config = item.config,
              from_prompt_library = item.from_prompt_library,
            }
          end
        end

        vim.schedule(function()
          callback(items)
        end)
      end)
    end

    local function trigger_complete()
      local line = vim.api.nvim_get_current_line()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local col = cursor[2]
      if col == 0 or #line == 0 then
        return
      end

      local before_cursor = line:sub(1, col)
      local find_current_word = string.find(before_cursor, "%s[^%s]*$")
      local start = find_current_word or 0
      local prefix = line:sub(start + 1, col)
      if not prefix then
        return
      end

      complete_items(function(items)
        vim.fn.complete(
          start + 1,
          vim.tbl_filter(function(item)
            return vim.startswith(item.word:lower(), prefix:lower())
          end, items)
        )
      end)
    end

    trigger_complete()
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
    chats[1].chat.ui:open()
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
local function yank_node(node)
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

M.pin_reference = {
  desc = "Pin Reference",
  callback = function(chat)
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(chat.bufnr, current_line - 1, current_line, true)[1]

    if not vim.startswith(line, "> - ") then
      return
    end

    local icon = config.display.chat.icons.pinned_buffer
    local id = line:gsub("^> %- ", "")

    if not chat.references:can_be_pinned(id) then
      return util.notify("This reference type cannot be pinned", vim.log.levels.WARN)
    end

    local filename = id
    local state = "unpinned"
    if line:find(icon) then
      state = "pinned"
      filename = filename:gsub(icon, "")
      id = filename
    end

    -- Update the UI
    local new_line = (state == "pinned") and string.format("> - %s", filename)
      or string.format("> - %s%s", icon, filename)
    api.nvim_buf_set_lines(chat.bufnr, current_line - 1, current_line, true, { new_line })

    -- Update the references on the chat buffer
    for _, ref in ipairs(chat.refs) do
      if ref.id == id then
        ref.opts.pinned = not ref.opts.pinned
        break
      end
    end
  end,
}

M.toggle_watch = {
  desc = "Toggle Watch Buffer",
  callback = function(chat)
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local line = vim.api.nvim_buf_get_lines(chat.bufnr, current_line - 1, current_line, true)[1]

    if not vim.startswith(line, "> - ") then
      return
    end

    local icons = config.display.chat.icons
    local id = line:gsub("^> %- ", "")
    if not chat.references:can_be_watched(id) then
      return util.notify("This reference type cannot be watched", vim.log.levels.WARN)
    end

    -- Find the reference and toggle watch state
    for _, ref in ipairs(chat.refs) do
      local clean_id = id:gsub(icons.pinned_buffer, ""):gsub(icons.watched_buffer, "")
      if ref.id == clean_id then
        if not ref.opts then
          ref.opts = {}
        end
        ref.opts.watched = not ref.opts.watched

        -- Update the UI for just this line
        local new_line
        if ref.opts.watched then
          -- Check if buffer is still valid before watching
          if vim.api.nvim_buf_is_valid(ref.bufnr) and vim.api.nvim_buf_is_loaded(ref.bufnr) then
            chat.watchers:watch(ref.bufnr)
            new_line = string.format("> - %s%s", icons.watched_buffer, clean_id)
          else
            -- Buffer is invalid, can't watch it
            ref.opts.watched = false
            new_line = string.format("> - %s", clean_id)
            util.notify("Cannot watch invalid or unloaded buffer " .. ref.id, vim.log.levels.WARN)
          end
        else
          chat.watchers:unwatch(ref.bufnr)
          new_line = string.format("> - %s", clean_id)
        end

        -- Update only the current line
        vim.api.nvim_buf_set_lines(chat.bufnr, current_line - 1, current_line, true, { new_line })
        break
      end
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
      return util.notify("Adapter can't be changed when `display.chat.show_settings = true`", vim.log.levels.WARN)
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
        util.fire(
          "ChatAdapter",
          { bufnr = chat.bufnr, adapter = require("codecompanion.adapters").make_safe(chat.adapter) }
        )
        chat.ui.adapter = chat.adapter
        chat:apply_settings()
      end

      -- Update the system prompt
      local system_prompt = config.opts.system_prompt
      if type(system_prompt) == "function" then
        if chat.messages[1] and chat.messages[1].role == "system" then
          chat.messages[1].content = system_prompt(chat.adapter)
        end
      end

      -- Select a model
      local models = chat.adapter.schema.model.choices
      if type(models) == "function" then
        models = models(chat.adapter)
      end
      if not models or vim.tbl_count(models) < 2 then
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
    chat.ui:fold_code()
  end,
}

M.debug = {
  desc = "Show debug information for the current chat",
  callback = function(chat)
    local settings, messages = chat:debug()
    if not settings and not messages then
      return
    end

    return require("codecompanion.strategies.chat.debug")
      .new({
        chat = chat,
        settings = settings,
      })
      :render()
  end,
}

M.toggle_system_prompt = {
  desc = "Toggle the system prompt",
  callback = function(chat)
    chat:toggle_system_prompt()
  end,
}

M.auto_tool_mode = {
  desc = "Toggle automatic tool mode",
  callback = function(chat)
    if vim.g.codecompanion_auto_tool_mode then
      vim.g.codecompanion_auto_tool_mode = nil
      return util.notify("Disabled automatic tool mode", vim.log.levels.INFO)
    else
      vim.g.codecompanion_auto_tool_mode = true
      return util.notify("Enabled automatic tool mode", vim.log.levels.INFO)
    end
  end,
}

return M
