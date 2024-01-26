local ts = require("codecompanion.utils.ts")

local M = {}

M.close = {
  desc = "Close the chat window",
  callback = function()
    vim.api.nvim_win_close(0, true)
  end,
}

M.delete = {
  desc = "Delete the current chat",
  callback = function()
    M.close.callback()
    table.remove(_G.codecompanion_chats, #_G.codecompanion_chats)
  end,
}

M.clear = {
  desc = "Clear the current chat",
  callback = function()
    local bufnr = vim.api.nvim_get_current_buf()

    local ns_id = vim.api.nvim_create_namespace("CodeCompanionTokens")
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
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
