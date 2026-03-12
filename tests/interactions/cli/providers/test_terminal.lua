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
