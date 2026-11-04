local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        chat = h.setup_chat_buffer()
        approvals = require("codecompanion.interactions.chat.tools.approvals")
        approvals:set_mode(chat.bufnr, { mode = "ask" })
        adapter = require("codecompanion.adapters").resolve("cursor_cli")
        results = {}

        function send(message)
          local responded = false
          local request = {
            chat = chat,
            message = message,
            respond = function(result)
              if responded then
                return
              end
              responded = true
              table.insert(results, { id = message.id, outcome = result.outcome })
            end,
            on_cancel = function(cancel)
              cancel_request = cancel
            end,
          }
          return adapter.handlers.request.agent_request(adapter, request)
        end

        function press(label)
          for _, map in ipairs(vim.api.nvim_buf_get_keymap(chat.bufnr, "n")) do
            if map.desc == label then
              return map.callback()
            end
          end
          error("No keymap for " .. label)
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Cursor CLI adapter"] = MiniTest.new_set()

T["Cursor CLI adapter"]["asks before accepting a plan in ask mode"] = function()
  local result = child.lua([[
    send({ id = 1, method = "cursor/create_plan", params = { name = "Plan", plan = "Do it" } })
    local before = #results
    press(require("codecompanion.interactions.chat.tools.labels").accept)
    return { before = before, results = results }
  ]])

  h.eq(0, result.before)
  h.eq({ { id = 1, outcome = { outcome = "accepted" } } }, result.results)
end

T["Cursor CLI adapter"]["accepts a plan without asking in auto and yolo mode"] = function()
  local result = child.lua([[
    approvals:set_mode(chat.bufnr, { mode = "auto" })
    send({ id = 2, method = "cursor/create_plan", params = { plan = "Do it" } })
    approvals:set_mode(chat.bufnr, { mode = "yolo" })
    send({ id = 3, method = "cursor/create_plan", params = { plan = "Do it" } })
    return results
  ]])

  h.eq({
    { id = 2, outcome = { outcome = "accepted" } },
    { id = 3, outcome = { outcome = "accepted" } },
  }, result)
end

T["Cursor CLI adapter"]["answers a question with the selected option"] = function()
  local result = child.lua([[
    send({
      id = 4,
      method = "cursor/ask_question",
      params = {
        questions = {
          { id = "q1", prompt = "Pick", options = { { id = "a", label = "A" }, { id = "b", label = "B" } } },
        },
      },
    })
    press("B")
    return results
  ]])

  h.eq({
    {
      id = 4,
      outcome = { outcome = "answered", answers = { { questionId = "q1", selectedOptionIds = { "b" } } } },
    },
  }, result)
end

T["Cursor CLI adapter"]["cancels a pending plan when the turn ends"] = function()
  local result = child.lua([[
    send({ id = 5, method = "cursor/create_plan", params = { plan = "Do it" } })
    cancel_request()
    return results
  ]])

  h.eq({ { id = 5, outcome = { outcome = "cancelled" } } }, result)
end

T["Cursor CLI adapter"]["rejects unsupported methods and ignores unknown ones"] = function()
  local result = child.lua([[
    local task_handled = send({ id = 6, method = "cursor/task", params = {} })
    local unknown_handled = send({ id = 7, method = "vendor/unknown", params = {} })
    return { task_handled = task_handled, unknown_handled = unknown_handled, results = results }
  ]])

  h.is_true(result.task_handled)
  h.is_false(result.unknown_handled)
  h.eq(1, #result.results)
  h.eq("rejected", result.results[1].outcome.outcome)
end

return T
