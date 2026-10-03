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

T["Inline"]["accepting the diff takes ONE undo step, however many hunks were resolved"] = function()
  local result = child.lua([[
    require("codecompanion.config").display.diff.enabled = true
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c" })
    local response = _G.edit({ old_string = "a\nb", new_string = "A\nb" })
    table.insert(response.tool_calls, _G.edit({ old_string = "b\nc", new_string = "b\nC" }).tool_calls[1])
    table.insert(_G.responses, response)

    _G.inline = _G.new_inline({ start_line = 1, end_line = 1, start_col = 0, end_col = 0 })
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

  local shared = child.lua_get([[_G.requests[1].messages[2].content]])
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

return T
