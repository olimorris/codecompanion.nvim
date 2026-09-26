local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        chat = h.setup_chat_buffer()

        local mcp = require("codecompanion.mcp")
        mcp.get_prompts = function(opts)
          opts.callback({
            {
              server = "github",
              prompt = {
                name = "issue_to_fix_workflow",
                arguments = {
                  { name = "title", required = true },
                  { name = "labels" },
                },
              },
            },
          })
        end

        REQUESTED_ARGUMENTS = nil
        mcp.get_prompt = function(opts)
          REQUESTED_ARGUMENTS = opts.arguments
          opts.callback(true, {
            messages = {
              { role = "user", content = { type = "text", text = "Create an issue titled " .. opts.arguments.title } },
              { role = "assistant", content = { type = "text", text = "I'll create the issue" } },
              { role = "user", content = { type = "image", data = "abc", mimeType = "image/png" } },
              { role = "user", content = { type = "text", text = "Then open a PR" } },
            },
          })
        end

        vim.ui.select = function(items, _, on_choice)
          on_choice(items[1])
        end

        function run_with_answers(answers)
          vim.ui.input = function(_, on_confirm)
            on_confirm(table.remove(answers, 1))
          end
          local SlashCommand = require("codecompanion.interactions.chat.slash_commands.builtin.mcp_prompts")
          SlashCommand.new({ Chat = chat, config = {}, context = {} }):execute()
          return table.concat(h.get_buf_lines(chat.bufnr), "\n")
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["MCP Prompts"] = MiniTest.new_set()

T["MCP Prompts"]["adds the text from user messages to the chat buffer"] = function()
  local result = child.lua([[
    local buffer = run_with_answers({ "Login bug", "" })
    return { buffer = buffer, arguments = REQUESTED_ARGUMENTS }
  ]])

  h.eq({ title = "Login bug" }, result.arguments)
  h.expect_contains("Create an issue titled Login bug\n\nThen open a PR", result.buffer)
  h.expect_not_contains("I'll create the issue", result.buffer)
end

T["MCP Prompts"]["DOES NOT get the prompt when a required argument is blank"] = function()
  local result = child.lua([[
    local buffer = run_with_answers({ "" })
    return { buffer = buffer, requested = REQUESTED_ARGUMENTS ~= nil }
  ]])

  h.is_false(result.requested)
  h.expect_not_contains("Create an issue", result.buffer)
end

return T
