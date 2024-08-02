local config = require("codecompanion").config

local ts = require("codecompanion.utils.treesitter")

local api = vim.api

local M = {}

---Clear a keymap from a specific buffer
---@param keys string
---@param bufnr? integer
local function clear_map(keys, bufnr)
  bufnr = bufnr or 0
  vim.keymap.del("n", keys, { buffer = bufnr })
end

-- CHAT MAPPINGS --------------------------------------------------------------
M.helpers = {
  callback = function()
    local lines = {}
    local indent = " "
    local padding = " "

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

    -- Output them to a floating window
    local window = config.display.chat.window
    local width = window.width > 1 and window.width or 85
    local height = window.height > 1 and window.height or 17

    local bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(bufnr, "filetype", "codecompanion")
    local winnr = api.nvim_open_win(bufnr, true, {
      relative = "cursor",
      border = "single",
      width = width,
      height = height,
      style = "minimal",
      row = 10,
      col = 0,
      title = "Help",
      title_pos = "center",
    })

    api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    local function close()
      api.nvim_buf_delete(bufnr, { force = true })
    end

    -- Set keymaps to close the float
    vim.keymap.set("n", "q", close, { buffer = bufnr })
    vim.keymap.set("n", "<ESC>", close, { buffer = bufnr })
  end,
}

M.send = {
  callback = function()
    vim.cmd("w")
  end,
}

M.close = {
  callback = function(chat)
    chat:close()
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

M.save_chat = {
  desc = "Save the current chat",
  callback = function(chat)
    local saved_chat = require("codecompanion.strategies.saved_chats")

    if chat.saved_chat then
      chat:save_chat()

      if config.opts.silence_notifications then
        return
      end

      return vim.notify("[CodeCompanion.nvim]\nChat has been saved", vim.log.levels.INFO)
    end

    vim.ui.input({ prompt = "Chat Name" }, function(filename)
      if not filename then
        return
      end
      saved_chat = saved_chat.new({ filename = filename })
      saved_chat:save(chat)
      chat.saved_chat = filename
    end)
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

M.next = {
  desc = "Go to the next message",
  callback = function()
    ts.goto_heading("next", 1)
  end,
}

M.previous = {
  desc = "Go to the previous message",
  callback = function()
    ts.goto_heading("prev", 1)
  end,
}

-- INLINE MAPPINGS ------------------------------------------------------------

M.accept_change = {
  desc = "Accept the change from the LLM",
  callback = function(inline)
    local ns_id = vim.api.nvim_create_namespace("codecompanion_diff_removed_")
    api.nvim_buf_clear_namespace(inline.context.bufnr, ns_id, 0, -1)

    for map, _ in pairs(config.strategies.inline.keymaps) do
      clear_map(map, inline.context.bufnr)
    end
  end,
}

M.reject_change = {
  desc = "Reject the change from the LLM",
  callback = function(inline)
    local ns_id = vim.api.nvim_create_namespace("codecompanion_diff_removed_")
    api.nvim_buf_clear_namespace(inline.context.bufnr, ns_id, 0, -1)
    vim.cmd("undo")

    for map, _ in pairs(config.strategies.inline.keymaps) do
      clear_map(map, inline.context.bufnr)
    end
  end,
}

return M
