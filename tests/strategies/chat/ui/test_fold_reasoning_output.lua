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

        -- Ensure reasoning folds are enabled and icon configured
        config.display = config.display or {}
        config.display.chat = config.display.chat or {}
        config.display.chat.fold_reasoning = true
        config.display.chat.icons = config.display.chat.icons or {}
        config.display.chat.icons.chat_fold = "XX"

        -- Fresh chat buffer
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

T["Reasoning folds"] = new_set()

T["Reasoning folds"]["creates fold from header+1 to before Response header"] = function()
  child.lua([[
    -- Stream a reasoning chunk
    _G.chat:add_buf_message({ role = "llm", content = "My usual text where I pretend I'm reasoning about something when I'm probably not" }, { type = _G.MT.REASONING_MESSAGE })
    -- Transition to response (this triggers folding via Builder)
    _G.chat:add_buf_message({ role = "llm", content = "Reasoning over. Time to respond" }, { type = _G.MT.LLM_MESSAGE })

    -- Allow scheduled fold creation to run
    vim.wait(200, function() return false end)
  ]])

  local res = child.lua([[
    local bufnr = _G.chat.bufnr
    local folds = require("codecompanion.strategies.chat.ui.folds").fold_summaries[bufnr] or {}

    -- Find the ### Reasoning header line (0-based)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local header_row0 = nil
    for i, l in ipairs(lines) do
      if l == "### Reasoning" then
        header_row0 = i - 1
        break
      end
    end

    local start0 = header_row0 and (header_row0 + 1) or nil
    local fold_entry = (start0 and folds[start0]) or nil
    local icon = (require("tests.config").display or {}).chat.icons.chat_fold or ""

    -- Compute one line inside the fold (1-based for foldclosed())
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

  -- Sanity: Reasoning header exists
  h.not_eq(res.header_row0, nil, "Expected to find '### Reasoning' header")

  -- Fold should start right below the header
  h.not_eq(res.start0, nil, "Expected fold start at header+1")
  h.eq(res.fold_exists, true, "Expected a reasoning fold entry")
  h.eq(res.fold_type, "reasoning", "Fold type should be 'reasoning'")

  -- Summary text should be the configured icon + ellipsis
  h.eq(res.fold_content, "  " .. res.icon .. " ...")

  -- Ensure it's actually closed in the buffer
  h.eq(res.is_closed, true, "Expected the reasoning fold to be closed")

  expect.reference_screenshot(child.get_screenshot())
end

T["Reasoning folds"]["does not fold when no body under header"] = function()
  child.lua([[
    -- Produce a reasoning header with no body (empty content)
    _G.chat:add_buf_message({ role = "llm", content = "" }, { type = _G.MT.REASONING_MESSAGE })
    -- Transition to response
    _G.chat:add_buf_message({ role = "llm", content = "final answer" }, { type = _G.MT.LLM_MESSAGE })

    vim.wait(200, function() return false end)
  ]])

  local res = child.lua([[
    local bufnr = _G.chat.bufnr
    local folds = require("codecompanion.strategies.chat.ui.folds").fold_summaries[bufnr] or {}

    -- Locate Reasoning header
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local header_row0 = nil
    for i, l in ipairs(lines) do
      if l == "### Reasoning" then
        header_row0 = i - 1
        break
      end
    end

    local start0 = header_row0 and (header_row0 + 1) or nil
    local fold_entry = (start0 and folds[start0]) or nil

    if not fold_entry then
      return { has_fold = false }
    end

    -- Verify the fold is actually closed and contains only blank lines
    local inside_line1 = start0 + 2 -- 1-based line inside the fold
    local s1 = vim.fn.foldclosed(inside_line1)
    local e1 = vim.fn.foldclosedend(inside_line1)
    local body = vim.api.nvim_buf_get_lines(bufnr, s1 - 1, e1, true)

    local blank_only = true
    for _, l in ipairs(body) do
      if vim.trim(l) ~= "" then
        blank_only = false
        break
      end
    end

    return {
      has_fold = true,
      is_closed = s1 ~= -1,
      blank_only = blank_only,
    }
  ]])

  if res.has_fold then
    h.eq(res.is_closed, true, "Fold should be closed when created")
    h.eq(res.blank_only, true, "Fold body should be blank-only when no reasoning content")
  else
    -- No fold is also acceptable when there is no body
    h.eq(res.has_fold, false)
  end
end

T["Reasoning folds"]["preserves earlier folds when adding a new reasoning fold"] = function()
  child.lua([[
    -- First reasoning block
    _G.chat:add_buf_message(
      { role = "llm", content = "phase 1: thinking...\nphase 1: more thoughts" },
      { type = _G.MT.REASONING_MESSAGE }
    )
    _G.chat:add_buf_message(
      { role = "llm", content = "phase 1: answer" },
      { type = _G.MT.LLM_MESSAGE }
    )

    -- Second reasoning block within the same section
    _G.chat:add_buf_message(
      { role = "llm", content = "phase 2: thinking...\nphase 2: more thoughts" },
      { type = _G.MT.REASONING_MESSAGE }
    )
    _G.chat:add_buf_message(
      { role = "llm", content = "phase 2: answer" },
      { type = _G.MT.LLM_MESSAGE }
    )

    -- Allow scheduled fold creation to run
    vim.wait(300, function() return false end)
  ]])

  expect.reference_screenshot(child.get_screenshot())
end

return T
