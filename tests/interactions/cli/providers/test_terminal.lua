local new_set = MiniTest.new_set
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    post_once = child.stop,
  },
})

T["Terminal provider"] = new_set()

T["Terminal provider"]["start() returns true with a valid command"] = function()
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    local provider = Terminal.new({
      bufnr = bufnr,
      agent = { cmd = "cat", args = {} },
    })

    local started = provider:start()
    return {
      started = started,
      is_running = provider:is_running(),
      chan_type = type(provider.chan),
    }
  ]])

  h.eq(true, result.started)
  h.eq(true, result.is_running)
  h.eq("number", result.chan_type)
end

T["Terminal provider"]["start() returns false with an invalid command"] = function()
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    local provider = Terminal.new({
      bufnr = bufnr,
      agent = { cmd = "nonexistent_binary_xyz", args = {} },
    })

    local started = provider:start()
    return {
      started = started,
      is_running = provider:is_running(),
    }
  ]])

  h.eq(false, result.started)
  h.eq(false, result.is_running)
end

T["Terminal provider"]["send() returns false when not running"] = function()
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    local provider = Terminal.new({
      bufnr = bufnr,
      agent = { cmd = "cat", args = {} },
    })

    return provider:send("hello")
  ]])

  h.eq(false, result)
end

T["Terminal provider"]["send() queues text only when submit is false"] = function()
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    local provider = Terminal.new({
      bufnr = bufnr,
      agent = { cmd = "cat", args = {} },
    })

    provider:start()
    -- Queue is drained once ready, so we test before readiness fires
    provider.ready = false
    provider:send("hello world")

    local items = provider.queue:contents()
    return {
      count = provider.queue:count(),
      first_text = items[1] and items[1].text,
      first_enter = items[1] and items[1].enter,
    }
  ]])

  h.eq(1, result.count)
  h.eq("hello world", result.first_text)
  h.eq(nil, result.first_enter)
end

T["Terminal provider"]["send() queues text and enter when submit is true"] = function()
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    local provider = Terminal.new({
      bufnr = bufnr,
      agent = { cmd = "cat", args = {} },
    })

    provider:start()
    provider.ready = false
    provider:send("hello world", { submit = true })

    local items = provider.queue:contents()
    return {
      count = provider.queue:count(),
      first_text = items[1] and items[1].text,
      second_enter = items[2] and items[2].enter,
    }
  ]])

  h.eq(2, result.count)
  h.eq("hello world", result.first_text)
  h.eq(true, result.second_enter)
end

--=============================================================================
-- chansend integration tests
--=============================================================================

T["Terminal provider"]["chansend delivers text to the terminal process"] = function()
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    local provider = Terminal.new({
      bufnr = bufnr,
      agent = { cmd = "cat", args = {} },
    })

    provider:start()
    -- cat won't produce enough output for readiness, so force it
    provider.ready = true
    provider:send("hello from chansend", { submit = true })

    -- Wait for the consumer timer to drain and cat to echo back
    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line:find("hello from chansend") then
          return true
        end
      end
      return false
    end)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found = false
    for _, line in ipairs(lines) do
      if line:find("hello from chansend") then
        found = true
        break
      end
    end

    provider:stop()
    return { text_delivered = found }
  ]])

  h.eq(true, result.text_delivered)
end

T["Terminal provider"]["chansend delivers multiple messages in order"] = function()
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    local provider = Terminal.new({
      bufnr = bufnr,
      agent = { cmd = "cat", args = {} },
    })

    provider:start()
    provider.ready = true
    provider:send("first_message", { submit = true })
    provider:send("second_message", { submit = true })

    -- Wait for both messages to appear
    vim.wait(3000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local found_first, found_second = false, false
      for _, line in ipairs(lines) do
        if line:find("first_message") then found_first = true end
        if line:find("second_message") then found_second = true end
      end
      return found_first and found_second
    end)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_first, found_second = false, false
    local first_pos, second_pos = nil, nil
    for i, line in ipairs(lines) do
      if line:find("first_message") and not found_first then
        found_first = true
        first_pos = i
      end
      if line:find("second_message") and not found_second then
        found_second = true
        second_pos = i
      end
    end

    provider:stop()
    return {
      first_delivered = found_first,
      second_delivered = found_second,
      correct_order = first_pos ~= nil and second_pos ~= nil and first_pos < second_pos,
    }
  ]])

  h.eq(true, result.first_delivered)
  h.eq(true, result.second_delivered)
  h.eq(true, result.correct_order)
end

T["Terminal provider"]["chansend normalizes CRLF to LF"] = function()
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    local provider = Terminal.new({
      bufnr = bufnr,
      agent = { cmd = "cat", args = {} },
    })

    provider:start()
    provider.ready = true

    -- Send text with CRLF line endings
    provider:send("line_one\r\nline_two", { submit = true })

    vim.wait(2000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line:find("line_two") then return true end
      end
      return false
    end)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_one, found_two = false, false
    for _, line in ipairs(lines) do
      if line:find("line_one") then found_one = true end
      if line:find("line_two") then found_two = true end
    end

    provider:stop()
    return {
      line_one = found_one,
      line_two = found_two,
    }
  ]])

  h.eq(true, result.line_one)
  h.eq(true, result.line_two)
end

T["Terminal provider"]["chansend without submit does not send enter"] = function()
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    local provider = Terminal.new({
      bufnr = bufnr,
      agent = { cmd = "cat", args = {} },
    })

    provider:start()
    provider.ready = true

    -- Send without submit — text goes to cat's stdin but no \r
    provider:send("no_submit_text")

    -- Give it time to be consumed
    vim.wait(500, function() return false end)

    -- Queue should be drained
    local queue_empty = provider.queue:is_empty()

    provider:stop()
    return { queue_empty = queue_empty }
  ]])

  h.eq(true, result.queue_empty)
end

T["Terminal provider"]["readiness detection transitions to ready and drains queue"] = function()
  -- Uses `echo` which produces output immediately, triggering readiness
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Use a command that produces enough output lines to trigger readiness
    local provider = Terminal.new({
      bufnr = bufnr,
      agent = {
        cmd = "sh",
        args = { "-c", "for i in 1 2 3 4 5 6 7 8; do echo ready_line_$i; done; cat" },
      },
    })

    provider:start()

    -- Queue a message before readiness — it should be drained automatically
    provider:send("after_ready", { submit = true })

    -- Wait for readiness + message delivery
    vim.wait(8000, function()
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for _, line in ipairs(lines) do
        if line:find("after_ready") then return true end
      end
      return false
    end)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_ready_lines = false
    local found_queued_msg = false
    for _, line in ipairs(lines) do
      if line:find("ready_line_") then found_ready_lines = true end
      if line:find("after_ready") then found_queued_msg = true end
    end

    provider:stop()
    return {
      became_ready = provider.ready,
      found_ready_lines = found_ready_lines,
      queued_msg_delivered = found_queued_msg,
    }
  ]])

  h.eq(true, result.became_ready)
  h.eq(true, result.found_ready_lines)
  h.eq(true, result.queued_msg_delivered)
end

T["Terminal provider"]["stop() clears the channel"] = function()
  local result = child.lua([[
    local Terminal = require("codecompanion.interactions.cli.providers.terminal")
    local bufnr = vim.api.nvim_create_buf(false, true)

    local provider = Terminal.new({
      bufnr = bufnr,
      agent = { cmd = "cat", args = {} },
    })

    provider:start()
    local running_before = provider:is_running()
    provider:stop()
    local running_after = provider:is_running()

    return {
      running_before = running_before,
      running_after = running_after,
    }
  ]])

  h.eq(true, result.running_before)
  h.eq(false, result.running_after)
end

return T
