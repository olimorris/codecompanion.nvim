local h = require("tests.helpers")

local new_set = MiniTest.new_set
local expect = MiniTest.expect
local child = MiniTest.new_child_neovim()

T = new_set()

T["cli()"] = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        local config = require("codecompanion.config")
        config.interactions.cli.agents = {
          test_agent_a = { cmd = "cat", args = {}, description = "Agent A" },
          test_agent_b = { cmd = "cat", args = {}, description = "Agent B" },
        }
        config.interactions.cli.agent = "test_agent_a"
        config.display.input.window.height = 5
        h.setup_plugin(config)
      ]])
    end,
    pre_case = function()
      child.lua([[
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          local name = vim.api.nvim_buf_get_name(bufnr)
          if name:find("%[CodeCompanion CLI%]") then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
          end
        end
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if win ~= vim.api.nvim_list_wins()[1] then
            pcall(vim.api.nvim_win_close, win, true)
          end
        end
        package.loaded["codecompanion.interactions.cli"] = nil
        package.loaded["codecompanion"] = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["cli()"]["with no args creates a new instance and opens it"] = function()
  local result = child.lua([[
    require("codecompanion").cli()

    local cli = require("codecompanion.interactions.cli")
    local instance = cli.last_cli()
    return {
      created = instance ~= nil,
      visible = instance and instance.ui:is_visible(),
      agent = instance and instance.agent_name,
    }
  ]])

  h.eq(true, result.created)
  h.eq(true, result.visible)
  h.eq("test_agent_a", result.agent)
end

T["cli()"]["with table arg uses opts (e.g. agent)"] = function()
  local result = child.lua([[
    require("codecompanion").cli({ agent = "test_agent_b" })

    local cli = require("codecompanion.interactions.cli")
    local instance = cli.last_cli()
    return {
      created = instance ~= nil,
      agent = instance and instance.agent_name,
    }
  ]])

  h.eq(true, result.created)
  h.eq("test_agent_b", result.agent)
end

T["cli()"]["with prompt reuses last instance"] = function()
  local result = child.lua([[
    local cc = require("codecompanion")
    local cli = require("codecompanion.interactions.cli")

    -- Create an initial instance
    cc.cli()
    local first_bufnr = cli.last_cli().bufnr

    -- Send a prompt — should reuse, not create new
    cc.cli("hello")
    local second_bufnr = cli.last_cli().bufnr

    return {
      same_instance = first_bufnr == second_bufnr,
    }
  ]])

  h.eq(true, result.same_instance)
end

T["cli()"]["with prompt and agent reuses matching agent instance"] = function()
  local result = child.lua([[
    local cc = require("codecompanion")
    local cli = require("codecompanion.interactions.cli")

    cc.cli({ agent = "test_agent_b" })
    local b_bufnr = cli.last_cli().bufnr

    cc.cli("hello", { agent = "test_agent_b" })
    local found = cli.find_by_agent("test_agent_b")

    return {
      same_instance = found and found.bufnr == b_bufnr,
    }
  ]])

  h.eq(true, result.same_instance)
end

T["cli()"]["focus=false does not open the UI"] = function()
  local result = child.lua([[
    local cc = require("codecompanion")
    local cli = require("codecompanion.interactions.cli")

    -- Create an instance first (closed)
    cli.create({ agent = "test_agent_a" })

    -- Send with focus=false — should not open
    cc.cli("hello", { focus = false })

    return {
      visible = cli.last_cli().ui:is_visible(),
    }
  ]])

  h.eq(false, result.visible)
end

T["cli()"]["prompt=true opens the input buffer"] = function()
  child.lua([[
    vim.cmd("enew")
    require("codecompanion").cli({ prompt = true })
  ]])
  expect.reference_screenshot(child.get_screenshot())
end

--=============================================================================
-- Visual selection
--=============================================================================

T["cli()"]["visual selection is included with the prompt"] = function()
  local result = child.lua([[
    -- Create a buffer with known content
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "line one",
      "line two",
      "line three",
      "line four",
    })
    vim.bo[buf].filetype = "lua"

    -- Set visual marks for lines 2-3
    vim.api.nvim_buf_set_mark(buf, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 3, 9, {})

    -- Intercept send to capture what gets sent
    local sent_text
    local cli = require("codecompanion.interactions.cli")
    local orig_send = cli.create({ agent = "test_agent_a" })
    local instance = cli.last_cli()
    local original_send = instance.send
    instance.send = function(self, text, opts)
      sent_text = text
    end

    -- Call cli with a prompt and simulated range
    require("codecompanion").cli("explain this", { args = { range = 2 }, focus = false })

    return {
      has_selection = sent_text ~= nil and sent_text:find("line two") ~= nil,
      has_line_three = sent_text ~= nil and sent_text:find("line three") ~= nil,
      has_prompt = sent_text ~= nil and sent_text:find("explain this") ~= nil,
      has_selected_code = sent_text ~= nil and sent_text:find("Selected code from") ~= nil,
    }
  ]])

  h.eq(true, result.has_selection)
  h.eq(true, result.has_line_three)
  h.eq(true, result.has_prompt)
  h.eq(true, result.has_selected_code)
end

T["cli()"]["visual selection is not duplicated when prompt contains #this"] = function()
  local result = child.lua([[
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "alpha",
      "beta",
      "gamma",
    })
    vim.bo[buf].filetype = "lua"

    vim.api.nvim_buf_set_mark(buf, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 2, 3, {})

    local sent_text
    local cli = require("codecompanion.interactions.cli")
    cli.create({ agent = "test_agent_a" })
    local instance = cli.last_cli()
    instance.send = function(self, text, opts)
      sent_text = text
    end

    require("codecompanion").cli("#{this}", { args = { range = 2 }, focus = false })

    -- Count occurrences of "alpha" — should appear only once
    local count = 0
    for _ in sent_text:gmatch("alpha") do
      count = count + 1
    end

    -- Count "Selected code from" — should appear exactly once (from #{this} resolving, not auto-prepend)
    local selected_count = 0
    for _ in sent_text:gmatch("Selected code from") do
      selected_count = selected_count + 1
    end

    return {
      has_content = sent_text ~= nil and sent_text:find("alpha") ~= nil,
      no_literal_this = sent_text:find("#{this}") == nil,
      alpha_count = count,
      selected_count = selected_count,
    }
  ]])

  h.eq(true, result.has_content)
  h.eq(true, result.no_literal_this)
  h.eq(1, result.alpha_count)
  h.eq(1, result.selected_count)
end

T["cli()"]["#this in normal mode sends buffer path"] = function()
  local result = child.lua([[
    vim.cmd("edit lua/codecompanion/init.lua")

    local sent_text
    local cli = require("codecompanion.interactions.cli")
    cli.create({ agent = "test_agent_a" })
    local instance = cli.last_cli()
    instance.send = function(self, text, opts)
      sent_text = text
    end

    require("codecompanion").cli("#{this}", { focus = false })

    return {
      has_path = sent_text ~= nil and sent_text:find("init.lua") ~= nil,
      no_selection = sent_text == nil or sent_text:find("Selected code from") == nil,
    }
  ]])

  h.eq(true, result.has_path)
  h.eq(true, result.no_selection)
end

T["cli()"]["empty prompt with visual selection sends only the selection"] = function()
  local result = child.lua([[
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "first",
      "second",
      "third",
    })
    vim.bo[buf].filetype = "lua"

    vim.api.nvim_buf_set_mark(buf, "<", 2, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 2, 5, {})

    local sent_text
    local cli = require("codecompanion.interactions.cli")
    cli.create({ agent = "test_agent_a" })
    local instance = cli.last_cli()
    instance.send = function(self, text, opts)
      sent_text = text
    end

    -- Empty prompt with range — simulates :'<,'>CodeCompanionCLI
    require("codecompanion").cli("", { args = { range = 2 }, focus = false })

    return {
      has_selection = sent_text ~= nil and sent_text:find("second") ~= nil,
      has_selected_code = sent_text ~= nil and sent_text:find("Selected code from") ~= nil,
      no_first = sent_text == nil or sent_text:find("first") == nil,
      no_third = sent_text == nil or sent_text:find("third") == nil,
    }
  ]])

  h.eq(true, result.has_selection)
  h.eq(true, result.has_selected_code)
  h.eq(true, result.no_first)
  h.eq(true, result.no_third)
end

T["cli()"]["without visual selection does not include selection content"] = function()
  local result = child.lua([[
    local sent_text
    local cli = require("codecompanion.interactions.cli")
    cli.create({ agent = "test_agent_a" })
    local instance = cli.last_cli()
    instance.send = function(self, text, opts)
      sent_text = text
    end

    -- Normal mode call — no range
    require("codecompanion").cli("hello world", { focus = false })

    return {
      text = sent_text,
      no_selected_code = sent_text == nil or sent_text:find("Selected code from") == nil,
    }
  ]])

  h.eq("hello world\n", result.text)
  h.eq(true, result.no_selected_code)
end

return T
