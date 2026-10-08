local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()

T["Inline"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        config = require("tests.config")

        inline = h.setup_inline({
          adapters = {
            http = {
              test_adapter = {
                opts = { tools = true },
                handlers = {
                  chat_output = function(self, data, tools)
                    for _, tool_call in ipairs(data.tool_calls or {}) do
                      table.insert(tools, tool_call)
                    end
                    return { status = "success", output = { role = "assistant", content = data.content } }
                  end,
                },
              },
            },
          },
          display = { diff = { enabled = false } },
        })

        _G.requests = {}
        _G.responses = {}
        require("codecompanion.http").new = function()
          return {
            send = function(_, payload, opts)
              table.insert(_G.requests, payload)
              local response = table.remove(_G.responses, 1)
              vim.schedule(function()
                opts.on_chunk(response)
                opts.on_done(nil)
              end)
              return { cancel = function() end }
            end,
          }
        end

        ---@param args { old_string: string, new_string: string }
        function _G.edit(args)
          return {
            tool_calls = {
              {
                id = "call_" .. math.random(1000),
                type = "function",
                ["function"] = {
                  name = "edit_file",
                  arguments = vim.json.encode({
                    old_string = args.old_string,
                    new_string = args.new_string,
                    replace_all = false,
                  }),
                },
              },
            },
          }
        end

        function _G.new_inline(buffer_context)
          return require("codecompanion.interactions.inline").new({
            buffer_context = vim.tbl_extend("force", { winnr = 0, bufnr = 0, filetype = "lua" }, buffer_context),
          })
        end

        ---@param text string
        ---@return number|nil index of the first sent message containing the text
        function _G.find_sent_message(text)
          for index, message in ipairs(_G.requests[1].messages) do
            if type(message.content) == "string" and message.content:find(text, 1, true) then
              return index
            end
          end
        end

        function _G.wait_for_requests()
          vim.wait(1000, function()
            return #_G.responses == 0
          end)
          vim.wait(20)
        end
      ]])
    end,
    post_case = function()
      child.lua([[inline = nil]])
    end,
    post_once = child.stop,
  },
})

T["Inline"]["edits stay inside the selection"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1", "local a = 1", "local b = 2" })
    table.insert(_G.responses, _G.edit({ old_string = "local a = 1", new_string = "local a = 10" }))

    _G.new_inline({ is_visual = true, start_line = 2, end_line = 2, start_col = 1, end_col = 11 }):prompt("Change a")
    _G.wait_for_requests()
  ]])

  h.eq({ "local a = 1", "local a = 10", "local b = 2" }, child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]]))
end

T["Inline"]["deleting everything in the selection removes its lines"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1", "local b = 2", "local c = 3" })
    table.insert(_G.responses, _G.edit({ old_string = "local b = 2", new_string = "" }))

    _G.new_inline({ is_visual = true, start_line = 2, end_line = 2, start_col = 1, end_col = 11 }):prompt("Delete b")
    _G.wait_for_requests()
  ]])

  h.eq({ "local a = 1", "local c = 3" }, child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]]))
end

T["Inline"]["applies every edit in a response"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1", "local b = 2" })
    local response = _G.edit({ old_string = "local a = 1", new_string = "local a = 10" })
    table.insert(response.tool_calls, _G.edit({ old_string = "local b = 2", new_string = "local b = 20" }).tool_calls[1])
    table.insert(_G.responses, response)

    _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 }):prompt("Multiply by 10")
    _G.wait_for_requests()
  ]])

  h.eq({ "local a = 10", "local b = 20" }, child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]]))
end

T["Inline"]["applies tool calls that the adapter only formats after parsing"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    table.insert(_G.responses, {
      tool_calls = {
        { id = "toolu_1", name = "edit_file", input = '{"old_string":"local a = 1","new_string":"local a = 10"}' },
      },
    })

    local inline = _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 })
    inline.adapter.handlers.tools.format_tool_calls = function(self, tools)
      return vim.tbl_map(function(tool)
        return { id = tool.id, type = "function", ["function"] = { name = tool.name, arguments = tool.input } }
      end, tools)
    end
    inline:prompt("Change a")
    _G.wait_for_requests()
  ]])

  h.eq({ "local a = 10" }, child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]]))
end

T["Inline"]["rejecting all hunks keeps the ones already accepted"] = function()
  child.lua([[
    require("codecompanion.config").display.diff.enabled = true
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c" })
    local response = _G.edit({ old_string = "a\nb", new_string = "A\nb" })
    table.insert(response.tool_calls, _G.edit({ old_string = "b\nc", new_string = "b\nC" }).tool_calls[1])
    table.insert(_G.responses, response)

    _G.inline = _G.new_inline({ bufnr = _G.edited_bufnr, start_line = 1, end_line = 1, start_col = 0, end_col = 0 })
    _G.inline:prompt("Capitalise the letters")
    _G.wait_for_requests()

    local diff_ui = _G.inline.diff_ui
    diff_ui:resolve_hunk(1, { accept = true })
    require("codecompanion.diff.keymaps").reject_change.callback(diff_ui)
  ]])

  h.eq({ "A", "b", "c" }, child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]]))
end

T["Inline"]["accepting the diff takes ONE undo step, however many hunks were resolved"] = function()
  local result = child.lua([[
    require("codecompanion.config").display.diff.enabled = true
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c" })
    local response = _G.edit({ old_string = "a\nb", new_string = "A\nb" })
    table.insert(response.tool_calls, _G.edit({ old_string = "b\nc", new_string = "b\nC" }).tool_calls[1])
    table.insert(_G.responses, response)

    _G.inline = _G.new_inline({ bufnr = _G.edited_bufnr, start_line = 1, end_line = 1, start_col = 0, end_col = 0 })
    _G.inline:prompt("Capitalise the letters")
    _G.wait_for_requests()

    -- Each keypress is its own undo block in real use
    local diff_ui = _G.inline.diff_ui
    vim.go.undolevels = vim.go.undolevels
    diff_ui:resolve_hunk(1, { accept = true })
    vim.go.undolevels = vim.go.undolevels
    require("codecompanion.diff.keymaps").accept_change.callback(diff_ui)
    local accepted = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    vim.cmd("silent undo")
    return { accepted = accepted, undone = vim.api.nvim_buf_get_lines(0, 0, -1, false) }
  ]])

  h.eq({ "A", "b", "C" }, result.accepted)
  h.eq({ "a", "b", "c" }, result.undone)
end

T["Inline"]["shares the lines around the cursor when the buffer is OUTSIDE the limit"] = function()
  child.lua([[
    local lines = {}
    for i = 1, 100 do
      table.insert(lines, "local variable_" .. i .. " = " .. i)
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    require("codecompanion.config").interactions.inline.opts.max_context_tokens = 50
    table.insert(_G.responses, { content = "Okay" })

    _G.new_inline({ start_line = 50, end_line = 50, start_col = 0, end_col = 0 }):prompt("Hello")
    _G.wait_for_requests()
  ]])

  local shared = child.lua_get([[_G.requests[1].messages[_G.find_sent_message("This is lines ")].content]])
  h.expect_starts_with("This is lines ", shared)
  h.expect_contains("local variable_50 = 50", shared)
  h.eq(nil, shared:find("local variable_1 = 1\n", 1, true))
end

T["Inline"]["retries a failed edit once, sending the error back"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    table.insert(_G.responses, _G.edit({ old_string = "local z = 1", new_string = "local a = 10" }))
    table.insert(_G.responses, _G.edit({ old_string = "local a = 1", new_string = "local a = 10" }))

    _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 }):prompt("Change a")
    _G.wait_for_requests()
  ]])

  h.eq(2, child.lua_get([[#_G.requests]]))
  local retried = child.lua_get([[_G.requests[2].messages]])
  h.expect_starts_with("Edit failed:", retried[#retried].content)
  h.eq({ "local a = 10" }, child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]]))
end

T["Inline"]["sends the autoloaded rules before the buffer"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    table.insert(_G.responses, { content = "Okay" })

    _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 }):prompt("Hello")
    _G.wait_for_requests()
    _G.positions = {
      rules = _G.find_sent_message("This is the test CLAUDE.md"),
      buffer = _G.find_sent_message("This is the whole buffer"),
    }
  ]])

  local positions = child.lua_get([[_G.positions]])
  h.eq(true, positions.rules < positions.buffer)
end

T["Inline"]["sends a file that is both listed and included by a rules file once"] = function()
  child.lua([[
    local agents_md = vim.fs.joinpath(vim.fn.tempname(), "AGENTS.md")
    vim.fn.mkdir(vim.fs.dirname(agents_md), "p")
    vim.fn.writefile({ "# Agents", "", "@tests/stubs/rules/.rules" }, agents_md)
    require("codecompanion.config").rules.default = {
      files = { { path = agents_md, parser = "claude" }, "tests/stubs/rules/.rules" },
    }
    table.insert(_G.responses, { content = "Okay" })

    _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 }):prompt("Hello")
    _G.wait_for_requests()
    _G.count = 0
    for _, message in ipairs(_G.requests[1].messages) do
      if message.content:find("This is a test .rules file", 1, true) then
        _G.count = _G.count + 1
      end
    end
  ]])

  h.eq(1, child.lua_get([[_G.count]]))
end

T["Inline"]["sends the full instructions of an autoloaded skill"] = function()
  child.lua([[
    local config = require("codecompanion.config")
    config.skills.dirs = { "tests/stubs/skills/project" }
    config.skills.opts.inline.autoload = { "house-style" }
    table.insert(_G.responses, { content = "Okay" })

    _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 }):prompt("Hello")
    _G.wait_for_requests()
  ]])

  h.eq(true, child.lua_get([[_G.find_sent_message("The project's own take.") ~= nil]]))
end

T["Inline"]["ACP"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        local connection = require("tests.mocks.acp").new({ adapter = require("codecompanion.adapters").resolve("test_acp") })
        require("codecompanion.acp").new = function()
          return connection
        end

        local session_prompt = connection.session_prompt
        connection.session_prompt = function(self, messages)
          _G.sent_prompt = messages[1].content
          return session_prompt(self, messages)
        end

        ---@return table handlers, string copy_path
        function _G.prompt_agent()
          local inline = _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 })
          inline:set_adapter("test_acp")
          inline:prompt("Change a")
          return _G.last_prompt_request.handlers, inline.request.copy_path
        end

        ---@return string option_id
        function _G.ask_to_edit(handlers, path)
          local chosen
          handlers.permission_request({
            tool_call = { kind = "edit", locations = { { path = path } } },
            options = { { kind = "allow_once", optionId = "allow" }, { kind = "reject_once", optionId = "reject" } },
            respond = function(option_id)
              chosen = option_id
            end,
          })
          return chosen
        end
      ]])
    end,
  },
})

T["Inline"]["ACP"]["edits the agent makes to the copy reach the buffer"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1", "local b = 2" })
    local handlers, copy_path = _G.prompt_agent()
    vim.fn.writefile({ "local a = 10", "local b = 2" }, copy_path)
    handlers.complete("end_turn")
    vim.wait(100)
  ]])

  h.eq({ "local a = 10", "local b = 2" }, child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]]))
end

T["Inline"]["ACP"]["tells the agent to edit the copy"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    local _, copy_path = _G.prompt_agent()
    _G.copy_path = copy_path
  ]])

  h.eq(true, child.lua_get([[_G.sent_prompt:find("Make changes by editing `" .. _G.copy_path .. "`", 1, true) ~= nil]]))
end

T["Inline"]["ACP"]["sends a prompt library system message to the agent"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    local inline = require("codecompanion.interactions.inline").new({
      buffer_context = { winnr = 0, bufnr = 0, filetype = "lua", start_line = 1, end_line = 1, start_col = 0, end_col = 0 },
      prompts = { { role = "system", content = "Always use snake_case" } },
    })
    inline:set_adapter("test_acp")
    inline:prompt("Change a")
  ]])

  h.eq(true, child.lua_get([[_G.sent_prompt:find("Always use snake_case", 1, true) ~= nil]]))
end

T["Inline"]["ACP"]["DOES NOT send rules to the agent"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    _G.prompt_agent()
  ]])

  h.eq(
    { has_buffer = true, has_rules = false },
    child.lua_get([[{
      has_buffer = _G.sent_prompt:find("local a = 1", 1, true) ~= nil,
      has_rules = _G.sent_prompt:find("This is the test CLAUDE.md", 1, true) ~= nil,
    }]])
  )
end

T["Inline"]["ACP"]["DOES NOT let the agent write any file but the copy"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    local _, copy_path = _G.prompt_agent()
    local connection = require("codecompanion.acp").new()
    connection._active_prompt = _G.last_prompt_request
    connection.send_result = function() end
    connection.send_error = function() end

    _G.real_path = vim.fn.tempname()
    for id, path in ipairs({ _G.real_path, copy_path }) do
      connection:handle_fs_write_file_request(id, { sessionId = connection.session_id, path = path, content = "edited" })
    end
    _G.written = { real = vim.uv.fs_stat(_G.real_path) ~= nil, copy = vim.fn.readfile(copy_path)[1] }
  ]])

  h.eq({ real = false, copy = "edited" }, child.lua_get([[_G.written]]))
end

T["Inline"]["ACP"]["DOES NOT send the prompt WHEN stopped while connecting"] = function()
  child.lua([[
    local connection = require("codecompanion.acp").new()
    local inline = _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 })
    local ensure_session = connection.ensure_session
    connection.ensure_session = function(self)
      inline:stop()
      return ensure_session(self)
    end
    inline:set_adapter("test_acp")
    inline:prompt("Change a")
  ]])

  h.eq(vim.NIL, child.lua_get([[_G.sent_prompt]]))
end

T["Inline"]["ACP"]["can prompt again after the agent cancels"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    local handlers = _G.prompt_agent()
    handlers.complete("canceled")
    _G.sent_prompt = nil
    _G.prompt_agent()
  ]])

  h.not_eq(vim.NIL, child.lua_get([[_G.sent_prompt]]))
end

T["Inline"]["ACP"]["DOES NOT allow the agent to edit any file but the copy"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    local handlers, copy_path = _G.prompt_agent()
    _G.decisions = { real = _G.ask_to_edit(handlers, "/project/inventory.lua"), copy = _G.ask_to_edit(handlers, copy_path) }
  ]])

  h.eq({ real = "reject", copy = "allow" }, child.lua_get([[_G.decisions]]))
end

return T
