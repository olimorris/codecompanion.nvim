local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require("tests.config")

        -- Fresh chat buffer
        _G.chat, _G.tools = h.setup_chat_buffer()
        _G.MT = _G.chat.MESSAGE_TYPES
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["UI"] = new_set()

T["UI"]["coalesces cursor moves requested in the same event-loop drain"] = function()
  local moves = child.lua([[
    _G.chat:add_buf_message({ role = "user", content = "hello" }, { type = _G.MT.USER_MESSAGE })
    _G.chat.ui:open()
    _G.moves = 0
    _G.chat.ui.follow = function()
      _G.moves = _G.moves + 1
    end

    _G.chat.ui:move_cursor(true)
    _G.chat.ui:move_cursor(true)
    _G.chat.ui:move_cursor(true)
    vim.wait(200, function() return false end)

    return _G.moves
  ]])

  h.eq(moves, 1)
end

T["UI"]["moves the cursor after every write queued before it has landed"] = function()
  local result = child.lua([[
    _G.chat:add_buf_message({ role = "user", content = "hello" }, { type = _G.MT.USER_MESSAGE })
    _G.chat.ui:open()
    _G.moves = 0
    _G.chat.ui.follow = function()
      _G.moves = _G.moves + 1
      _G.lines_at_move = vim.api.nvim_buf_line_count(_G.chat.bufnr)
    end

    _G.chat:add_buf_message({ role = "llm", content = "one" }, { type = _G.MT.LLM_MESSAGE })
    _G.chat:add_buf_message({ role = "llm", content = "two" }, { type = _G.MT.LLM_MESSAGE })
    _G.chat:add_buf_message({ role = "llm", content = "three" }, { type = _G.MT.LLM_MESSAGE })
    vim.wait(200, function() return false end)

    return {
      moves = _G.moves,
      lines_at_move = _G.lines_at_move,
      line_count = vim.api.nvim_buf_line_count(_G.chat.bufnr),
    }
  ]])

  h.eq(result.moves, 1)
  h.eq(result.lines_at_move, result.line_count)
end

T["UI"]["does not schedule a cursor move when auto_scroll is off"] = function()
  local result = child.lua([[
    require("codecompanion.config").display.chat.auto_scroll = false
    _G.chat.ui:open()
    _G.moves = 0
    _G.chat.ui.follow = function()
      _G.moves = _G.moves + 1
    end

    _G.chat.ui:move_cursor(true)
    local pending = _G.chat.ui.follow_move_pending
    vim.wait(200, function() return false end)

    return { pending = pending, moves = _G.moves }
  ]])

  h.eq(result.pending, false)
  h.eq(result.moves, 0)
end

return T
