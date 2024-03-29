local config = require("codecompanion.config")
local ts = require("codecompanion.utils.ts")

local M = {}

M.save = {
  desc = "Save the chat buffer and trigger the API",
  callback = function()
    vim.cmd("w")
  end,
}

M.close = {
  desc = "Close the chat window",
  callback = function(args)
    vim.api.nvim_exec_autocmds(
      "User",
      { pattern = "CodeCompanionChat", data = { action = "close_buffer", buf = args.bufnr } }
    )
  end,
}

M.cancel_request = {
  desc = "Cancel the current request",
  callback = function(args)
    if _G.codecompanion_jobs[args.bufnr] == nil then
      return
    end
    vim.api.nvim_exec_autocmds(
      "User",
      { pattern = "CodeCompanionRequest", data = { buf = args.bufnr, action = "cancel_request" } }
    )
  end,
}

M.save_chat = {
  desc = "Save the current chat",
  callback = function(args)
    local chat = require("codecompanion.strategies.chat")
    local saved_chat = require("codecompanion.strategies.saved_chats").new({})

    if args.saved_chat then
      saved_chat.filename = args.saved_chat
      saved_chat:save(args.bufnr, chat.buf_get_messages(args.bufnr))

      if config.options.silence_notifications then
        return
      end

      return vim.notify("[CodeCompanion.nvim]\nChat has been saved", vim.log.levels.INFO)
    end

    vim.ui.input({ prompt = "Chat Name" }, function(filename)
      if not filename then
        return
      end
      saved_chat.filename = filename
      saved_chat:save(args.bufnr, chat.buf_get_messages(args.bufnr))
      args.saved_chat = filename
    end)
  end,
}

M.clear = {
  desc = "Clear the current chat",
  callback = function(args)
    local ns_id = vim.api.nvim_create_namespace("CodeCompanionTokens")
    vim.api.nvim_buf_clear_namespace(args.bufnr, ns_id, 0, -1)

    vim.api.nvim_buf_set_lines(args.bufnr, 0, -1, false, {})
  end,
}

M.codeblock = {
  desc = "Insert a codeblock",
  callback = function(args)
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local line = cursor_pos[1]

    args.type = args.type or ""

    local codeblock = {
      "```" .. args.type,
      "",
      "```",
    }

    vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, codeblock)
    vim.api.nvim_win_set_cursor(0, { line + 1, vim.fn.indent(line) })
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

return M
