local config = require("codecompanion.config")
local ts = require("codecompanion.utils.ts")

local M = {}

M.close = {
  desc = "Close the chat window",
  callback = function()
    vim.cmd("bd!")
  end,
}

M.cancel_request = {
  desc = "Cancel the current request",
  callback = function(args)
    if _G.codecompanion_jobs[args.bufnr] == nil then
      return
    end
    _G.codecompanion_jobs[args.bufnr].status = "stopping"
  end,
}

M.delete = {
  desc = "Delete the current chat",
  callback = function()
    M.close.callback()
    table.remove(_G.codecompanion_chats, #_G.codecompanion_chats)
  end,
}

M.save_conversation = {
  desc = "Save the chat as a conversation",
  callback = function(args)
    local chat = require("codecompanion.strategy.chat")
    local conversation = require("codecompanion.strategy.conversation").new({})

    if args.conversation then
      conversation.filename = args.conversation
      conversation:save(args.bufnr, chat.buf_get_messages(args.bufnr))

      if config.options.silence_notifications then
        return
      end

      return vim.notify("[CodeCompanion.nvim]\nConversation has been saved", vim.log.levels.INFO)
    end

    vim.ui.input({ prompt = "Conversation Name" }, function(filename)
      if not filename then
        return
      end
      conversation.filename = filename
      conversation:save(args.bufnr, chat.buf_get_messages(args.bufnr))
      args.conversation = filename
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
    ts.goto_heading("next")
  end,
}

M.previous = {
  desc = "Go to the previous message",
  callback = function()
    ts.goto_heading("prev")
  end,
}

return M
