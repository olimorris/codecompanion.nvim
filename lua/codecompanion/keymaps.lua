local ts = require("codecompanion.utils.ts")

local M = {}

M.close = {
  desc = "Close the chat window",
  callback = function()
    vim.api.nvim_win_close(0, true)
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
