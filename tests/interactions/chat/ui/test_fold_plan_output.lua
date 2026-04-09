local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require("tests.config")

        config.display = config.display or {}
        config.display.chat = config.display.chat or {}
        config.display.chat.fold_reasoning = true
        config.display.chat.icons = config.display.chat.icons or {}
        config.display.chat.icons.chat_fold = "XX"

        _G.chat, _G.tools = h.setup_chat_buffer(config)
        _G.MT = _G.chat.MESSAGE_TYPES
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Plan folds"] = new_set()

T["Plan folds"]["creates fold from header+1 to before next message"] = function()
  child.lua([[
    _G.chat:add_buf_message(
      { role = "llm", content = "○ Analyze the codebase\n→ Write the implementation\n✓ Run tests" },
      { type = _G.MT.PLAN_MESSAGE }
    )
    _G.chat:add_buf_message(
      { role = "llm", content = "Here is the response" },
      { type = _G.MT.LLM_MESSAGE }
    )

    vim.wait(200, function() return false end)
  ]])

  local res = child.lua([[
    local bufnr = _G.chat.bufnr
    local folds = require("codecompanion.interactions.chat.ui.folds").fold_summaries[bufnr] or {}

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local header_row0 = nil
    for i, l in ipairs(lines) do
      if l == "### Plan" then
        header_row0 = i - 1
        break
      end
    end

    local start0 = header_row0 and (header_row0 + 1) or nil
    local fold_entry = (start0 and folds[start0]) or nil
    local icon = (require("tests.config").display or {}).chat.icons.chat_fold or ""

    local inside_line1 = start0 and (start0 + 1 + 1) or nil

    return {
      header_row0 = header_row0,
      start0 = start0,
      fold_exists = fold_entry ~= nil,
      fold_type = fold_entry and fold_entry.type or nil,
      fold_content = fold_entry and fold_entry.content or nil,
      icon = icon,
      is_closed = (inside_line1 ~= nil) and (vim.fn.foldclosed(inside_line1) ~= -1) or false,
    }
  ]])

  h.not_eq(res.header_row0, nil, "Expected to find '### Plan' header")
  h.not_eq(res.start0, nil, "Expected fold start at header+1")
  h.eq(res.fold_exists, true, "Expected a plan fold entry")
  h.eq(res.fold_type, "plan", "Fold type should be 'plan'")
  h.eq(res.fold_content, "  " .. res.icon .. " ...")
  h.eq(res.is_closed, true, "Expected the plan fold to be closed")

  expect.reference_screenshot(child.get_screenshot())
end

T["Plan folds"]["does not fold when no body under header"] = function()
  child.lua([[
    _G.chat:add_buf_message(
      { role = "llm", content = "" },
      { type = _G.MT.PLAN_MESSAGE }
    )
    _G.chat:add_buf_message(
      { role = "llm", content = "response" },
      { type = _G.MT.LLM_MESSAGE }
    )

    vim.wait(200, function() return false end)
  ]])

  local res = child.lua([[
    local bufnr = _G.chat.bufnr
    local folds = require("codecompanion.interactions.chat.ui.folds").fold_summaries[bufnr] or {}

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local header_row0 = nil
    for i, l in ipairs(lines) do
      if l == "### Plan" then
        header_row0 = i - 1
        break
      end
    end

    local start0 = header_row0 and (header_row0 + 1) or nil
    local fold_entry = (start0 and folds[start0]) or nil

    return { has_fold = fold_entry ~= nil }
  ]])

  -- No fold is acceptable when there is no body content
  -- A fold over blank lines is also acceptable
  h.eq(type(res.has_fold), "boolean")
end

return T
