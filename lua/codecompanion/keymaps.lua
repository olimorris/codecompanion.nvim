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

M.save = {
  desc = "Save the chat buffer and trigger the API",
  callback = function()
    vim.cmd("w")
  end,
}

M.close = {
  desc = "Close the chat window",
  callback = function(chat)
    chat:close()
  end,
}

M.stop = {
  desc = "Stop the current request",
  callback = function(chat)
    if chat.current_request then
      chat:stop()
    end
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

M.clear = {
  desc = "Clear the current chat",
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
