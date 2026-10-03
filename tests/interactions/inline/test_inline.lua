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
              fake_adapter = { name = "fake_adapter" },
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
                opts.on_done(response)
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

    _G.inline = _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 })
    _G.inline:prompt("Capitalise the letters")
    _G.wait_for_requests()

    local diff_ui = _G.inline.diff_ui
    diff_ui:resolve_hunk(1, { accept = true })
    require("codecompanion.diff.keymaps").reject_change.callback(diff_ui)
  ]])

  h.eq({ "A", "b", "c" }, child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]]))
end

T["Inline"]["shares the whole buffer when it is INSIDE the limit"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1", "local b = 2", "local c = 3" })
    table.insert(_G.responses, { content = "Okay" })

    _G.new_inline({ start_line = 2, end_line = 2, start_col = 0, end_col = 0 }):prompt("Hello")
    _G.wait_for_requests()
  ]])

  h.expect_starts_with("This is the whole buffer", child.lua_get([[_G.requests[1].messages[2].content]]))
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

  local shared = child.lua_get([[_G.requests[1].messages[2].content]])
  h.expect_starts_with("This is lines ", shared)
  h.expect_contains("local variable_50 = 50", shared)
  h.eq(nil, shared:find("local variable_1 = 1\n", 1, true))
end

T["Inline"]["refuses a selection that is OUTSIDE the limit"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { string.rep("word ", 100) })
    require("codecompanion.config").interactions.inline.opts.max_context_tokens = 10

    _G.new_inline({ is_visual = true, start_line = 1, end_line = 1, start_col = 1, end_col = 500 }):prompt("Hello")
  ]])

  h.eq(0, child.lua_get([[#_G.requests]]))
end

T["Inline"]["refuses an adapter that can't call tools"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    local inline = _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 })
    inline.adapter.opts.tools = false
    inline:prompt("Hello")
  ]])

  h.eq(0, child.lua_get([[#_G.requests]]))
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

T["Inline"]["names the keys it received when old_string is missing"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    local response = _G.edit({ old_string = "local a = 1", new_string = "local a = 10" })
    response.tool_calls[1]["function"].arguments = '{"new_string=": -1, "replace_all": false}'
    table.insert(_G.responses, response)
    table.insert(_G.responses, { content = "Sorry" })

    _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 }):prompt("Change a")
    _G.wait_for_requests()
  ]])

  local retried = child.lua_get([[_G.requests[2].messages]])
  h.expect_contains("the keys you sent were `new_string=`, `replace_all`", retried[#retried].content)
end

T["Inline"]["fires the started and finished events once, with the bufnr, WHEN an edit is retried"] = function()
  child.lua([[
    _G.events = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = { "CodeCompanionInlineStarted", "CodeCompanionInlineFinished" },
      callback = function(event)
        table.insert(_G.events, { name = event.match, bufnr = event.data.bufnr })
      end,
    })

    _G.code_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    table.insert(_G.responses, _G.edit({ old_string = "local z = 1", new_string = "local a = 10" }))
    table.insert(_G.responses, _G.edit({ old_string = "local a = 1", new_string = "local a = 10" }))

    _G.new_inline({ bufnr = _G.code_bufnr, start_line = 1, end_line = 1, start_col = 0, end_col = 0 }):prompt("Change a")
    _G.wait_for_requests()
  ]])

  local bufnr = child.lua_get([[_G.code_bufnr]])
  h.eq({
    { name = "CodeCompanionInlineStarted", bufnr = bufnr },
    { name = "CodeCompanionInlineFinished", bufnr = bufnr },
  }, child.lua_get([[_G.events]]))
end

T["Inline"]["DOES NOT retry a failed edit more than once"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    for _ = 1, 3 do
      table.insert(_G.responses, _G.edit({ old_string = "local z = 1", new_string = "local a = 10" }))
    end

    _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 }):prompt("Change a")
    vim.wait(100)
  ]])

  h.eq(2, child.lua_get([[#_G.requests]]))
  h.eq({ "local a = 1" }, child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, false)]]))
end

T["Inline"]["opens a chat when the LLM replies without editing"] = function()
  child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    table.insert(_G.responses, { content = "It sets a to 1" })

    _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 }):prompt("What does this do?")
    _G.wait_for_requests()
  ]])

  local contents = child.lua_get([[vim.tbl_map(function(message)
    return message.content
  end, require("codecompanion").last_chat().messages)]])
  h.expect_tbl_contains("<prompt>What does this do?</prompt>", contents)
  h.expect_tbl_contains("It sets a to 1", contents)
end

T["Inline"]["asks for a prompt in the input box when there isn't one"] = function()
  child.lua([[
    _G.code_bufnr = vim.api.nvim_get_current_buf()
    local Inline = require("codecompanion.interactions.inline")
    function Inline:prompt(prompt)
      _G.prompted = { bufnr = self.bufnr, prompt = prompt }
    end

    require("codecompanion").inline({ args = "" })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Add a docstring" })
    vim.cmd("write")
  ]])

  h.eq({ bufnr = child.lua_get([[_G.code_bufnr]]), prompt = "Add a docstring" }, child.lua_get([[_G.prompted]]))
end

T["Inline"]["can be called from the action palette"] = function()
  child.lua([[
    local prompt = {
      name = "test",
      strategy = "inline",
      prompts = {
        {
          role = "user",
          content = "Action Palette test",
        },
      },
    }

    local interaction = require("codecompanion.interactions").new({
      buffer_context = inline.buffer_context,
      selected = prompt,
    })
    interaction:start("inline")

    _G.test_interaction = interaction
  ]])

  -- System prompt, then the buffer, then the user prompt
  h.eq(3, child.lua([[return #_G.test_interaction.called.prompts]]))
  h.eq("Action Palette test", child.lua([[return _G.test_interaction.called.prompts[3].content]]))
end

T["Inline"]["the first word can be an adapter"] = function()
  child.lua([[
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end
  ]])

  h.eq(child.lua([[return inline.adapter.name]]), "test_adapter")

  child.lua([[
    require("codecompanion.config").adapters.http.fake_adapter.opts = { tools = true }
    inline:prompt("fake_adapter print hello world")
  ]])

  h.eq("fake_adapter", child.lua([[return inline.adapter.name]]))

  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq("<prompt>print hello world</prompt>", submitted_prompts[#submitted_prompts].content)
end

T["Inline"]["integration"] = function()
  child.lua([[
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end

    inline:prompt("#{foo} can you print hello world?")
  ]])

  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq("The output from foo editor context", submitted_prompts[3].content)
  h.eq("<prompt>can you print hello world?</prompt>", submitted_prompts[4].content)
end

T["Inline"]["clears the stop keymap as soon as the request completes"] = function()
  child.lua([[
    require("codecompanion.http").new = function()
      return {
        send = function(_, _, opts)
          opts.on_error({ message = "network error" })
          return { cancel = function() end }
        end,
      }
    end

    inline:submit({ { role = "user", content = "test prompt" } })
  ]])

  local has_stop_keymap = child.lua([[
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
      if map.lhs == "q" then
        return true
      end
    end
    return false
  ]])

  h.eq(false, has_stop_keymap)
end

T["Inline"]["can parse adapter syntax"] = function()
  child.lua([[
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end

    require("codecompanion.config").adapters.http.fake_adapter.opts = { tools = true }
    require("codecompanion.config").interactions.inline.editor_context.buffer = {
      callback = function()
        return "mocked buffer content"
      end,
      description = "Mock buffer for testing",
    }
  ]])

  h.eq(child.lua([[return inline.adapter.name]]), "test_adapter")

  child.lua([[inline:prompt("adapter=fake_adapter #{buffer} print hello world")]])
  h.eq("fake_adapter", child.lua([[return inline.adapter.name]]))

  -- System prompt, the buffer, the editor context and the user prompt
  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq(4, #submitted_prompts)
  h.eq("mocked buffer content", submitted_prompts[3].content)
  h.eq("<prompt>print hello world</prompt>", submitted_prompts[4].content)
end

return T
