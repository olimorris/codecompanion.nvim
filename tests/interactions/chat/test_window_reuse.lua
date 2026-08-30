local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        local config = require("codecompanion.config")
        config.rules.opts.chat.enabled = false
        h.setup_plugin(config)
      ]])
    end,
    pre_case = function()
      child.lua([[
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          local name = vim.api.nvim_buf_get_name(bufnr)
          if name:find("%[CodeCompanion%]") then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
          end
        end
        local wins = vim.api.nvim_list_wins()
        for i = 2, #wins do
          pcall(vim.api.nvim_win_close, wins[i], true)
        end
        package.loaded["codecompanion.interactions.chat"] = nil
        package.loaded["codecompanion.interactions.shared.registry"] = nil
        package.loaded["codecompanion"] = nil
        h = require("tests.helpers")
        local config = require("codecompanion.config")
        config.rules.opts.chat.enabled = false
        h.setup_plugin(config)
      ]])
    end,
    post_once = child.stop,
  },
})

T["Window reuse"] = new_set()

T["Window reuse"]["cycling chats in a sole window does not error"] = function()
  local result = child.lua([[
    vim.cmd("CodeCompanionChat")
    vim.cmd("CodeCompanionChat")

    local chat = require("codecompanion").last_chat()
    vim.api.nvim_set_current_win(chat.ui.winnr)
    vim.cmd("only")

    local winnr_before = vim.api.nvim_get_current_win()
    local bufnr_before = vim.api.nvim_get_current_buf()
    local ok, err = pcall(function()
      require("codecompanion.interactions.chat.keymaps").next_chat.callback(chat)
    end)

    local chat_after = require("codecompanion").last_chat()
    return {
      ok = ok,
      err = ok and vim.NIL or tostring(err),
      same_win = vim.api.nvim_get_current_win() == winnr_before,
      buf_changed = vim.api.nvim_get_current_buf() ~= bufnr_before,
      filetype = vim.bo[vim.api.nvim_get_current_buf()].filetype,
      visible = chat_after.ui:is_visible(),
    }
  ]])

  h.eq(true, result.ok)
  h.eq(vim.NIL, result.err)
  h.eq(true, result.same_win)
  h.eq(true, result.buf_changed)
  h.eq("codecompanion", result.filetype)
  h.eq(true, result.visible)
end

T["Window reuse"]["cycling preserves layout and size"] = function()
  local result = child.lua([[
    vim.cmd("CodeCompanionChat")
    local chat1 = require("codecompanion").last_chat()
    local winnr = chat1.ui.winnr
    vim.api.nvim_set_current_win(winnr)
    vim.cmd("wincmd K")
    winnr = vim.api.nvim_get_current_win()
    chat1.ui.winnr = winnr
    vim.api.nvim_win_set_height(winnr, 12)

    local height_before = vim.api.nvim_win_get_height(winnr)
    local layout_before = vim.fn.winlayout()

    vim.cmd("CodeCompanionChat")
    local chat2 = require("codecompanion").last_chat()
    local ok, err = pcall(function()
      require("codecompanion.interactions.chat.keymaps").previous_chat.callback(chat2)
    end)

    local chat_after = require("codecompanion").last_chat()
    return {
      ok = ok,
      err = ok and vim.NIL or tostring(err),
      same_win = chat_after.ui.winnr == winnr,
      height_before = height_before,
      height_after = vim.api.nvim_win_get_height(winnr),
      layout_same = vim.deep_equal(layout_before, vim.fn.winlayout()),
    }
  ]])

  h.eq(true, result.ok)
  h.eq(vim.NIL, result.err)
  h.eq(true, result.same_win)
  h.eq(true, result.layout_same)
  h.eq(result.height_before, result.height_after)
end

T["Window reuse"]["new chat reuses window and sets filetype"] = function()
  local result = child.lua([[
    vim.cmd("CodeCompanionChat")
    local chat1 = require("codecompanion").last_chat()
    local winnr = chat1.ui.winnr
    vim.api.nvim_set_current_win(winnr)
    vim.cmd("wincmd K")
    winnr = vim.api.nvim_get_current_win()
    chat1.ui.winnr = winnr
    local height_before = vim.api.nvim_win_get_height(winnr)
    local layout_before = vim.fn.winlayout()

    vim.cmd("CodeCompanionChat")
    local chat2 = require("codecompanion").last_chat()

    return {
      same_win = chat2.ui.winnr == winnr,
      filetype = vim.bo[chat2.bufnr].filetype,
      height_before = height_before,
      height_after = vim.api.nvim_win_get_height(winnr),
      layout_same = vim.deep_equal(layout_before, vim.fn.winlayout()),
      different_chat = chat1.bufnr ~= chat2.bufnr,
    }
  ]])

  h.eq(true, result.same_win)
  h.eq("codecompanion", result.filetype)
  h.eq(true, result.different_chat)
  h.eq(true, result.layout_same)
  h.eq(result.height_before, result.height_after)
end

T["Window reuse"]["show_in_win sets filetype without shared_ui.open"] = function()
  local result = child.lua([[
    local chat = require("codecompanion").chat({ hidden = true })
    local filetype_before = vim.bo[chat.bufnr].filetype

    vim.cmd("vsplit")
    local winnr = vim.api.nvim_get_current_win()
    chat.ui:show_in_win({ winnr = winnr })

    return {
      filetype_before = filetype_before,
      filetype_after = vim.bo[chat.bufnr].filetype,
      visible = chat.ui:is_visible(),
      winnr = chat.ui.winnr == winnr,
    }
  ]])

  h.eq("", result.filetype_before)
  h.eq("codecompanion", result.filetype_after)
  h.eq(true, result.visible)
  h.eq(true, result.winnr)
end

return T
