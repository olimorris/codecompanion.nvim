local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.chat = h.setup_chat_buffer({ display = { chat = { input = { layout = "split" } } } })
        _G.input = chat.ui.input

        _G.write = function(lines)
          vim.api.nvim_buf_set_lines(input.bufnr, 0, -1, false, lines)
        end
        _G.input_lines = function()
          return vim.api.nvim_buf_get_lines(input.bufnr, 0, -1, false)
        end
        _G.chat_lines = function()
          return vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false)
        end
        _G.respond = function(message)
          chat:add_buf_message({ role = "llm", content = message })
          chat.status = "success"
          chat:done({ output = { message } })
        end
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Input"] = new_set()

T["Input"]["opens beneath the chat window with the cursor in it"] = function()
  local result = child.lua([[
    local chat_row = vim.fn.win_screenpos(chat.ui.winnr)[1]
    local input_row = vim.fn.win_screenpos(input.winnr)[1]
    return {
      below = input_row > chat_row,
      current = vim.api.nvim_get_current_win() == input.winnr,
      height = vim.api.nvim_win_get_height(input.winnr),
      configured_height = require("codecompanion.config").display.chat.input.height,
    }
  ]])

  h.eq(true, result.below)
  h.eq(true, result.current)
  h.eq(result.configured_height, result.height)
end

T["Input"]["is not created for the float layout"] = function()
  local has_input = child.lua([[
    local float_chat = require("codecompanion.interactions.chat").new({
      buffer_context = { bufnr = 1, filetype = "lua" },
      adapter = "test_adapter",
      window_opts = { layout = "float" },
    })
    return float_chat.ui.input ~= nil
  ]])

  h.eq(false, has_input)
end

T["Input"]["writes the prompt into the chat buffer under a user header on submit"] = function()
  local result = child.lua([[
    write({ "What does this do?" })
    h.send_to_llm(chat, "It does things")
    return {
      chat = chat_lines(),
      input = input_lines(),
      message = chat.messages[#chat.messages - 1].content,
    }
  ]])

  h.eq("What does this do?", result.message)
  h.eq({ "" }, result.input)
  h.eq("## foo", result.chat[1])
  h.expect_contains("What does this do?", table.concat(result.chat, "\n"))
end

T["Input"]["keeps the context block in the input and OUT of the chat buffer"] = function()
  local result = child.lua([[
    chat.context:add({ id = "<buf>foo.lua</buf>", source = "test" })
    write({ "> Context:", "> - <buf>foo.lua</buf>", "", "Explain this" })
    h.send_to_llm(chat, "Done")
    return { chat = chat_lines(), input = input_lines() }
  ]])

  h.eq(false, vim.tbl_contains(result.chat, "> Context:"))
  h.eq({ "> Context:", "> - <buf>foo.lua</buf>", "", "" }, result.input)
end

T["Input"]["does not add an empty user header once the response has finished"] = function()
  local last_line = child.lua([[
    write({ "Hello" })
    h.send_to_llm(chat, "Hi there")
    local lines = chat_lines()
    return lines[#lines]
  ]])

  h.eq("Hi there", last_line)
end

T["Input"]["keeps the chat buffer locked after a response"] = function()
  local modifiable = child.lua([[
    write({ "Hello" })
    h.send_to_llm(chat, "Hi there")
    return vim.bo[chat.bufnr].modifiable
  ]])

  h.eq(false, modifiable)
end

T["Input"]["sends a prompt submitted AFTER the response has finished"] = function()
  local result = child.lua([[
    write({ "First" })
    h.send_to_llm(chat, "One")
    write({ "Second" })
    h.send_to_llm(chat, "Two")
    return vim.tbl_map(function(message)
      return message.content
    end, vim.tbl_filter(function(message)
      return message.role == "user"
    end, chat.messages))
  ]])

  h.eq({ "First", "Second" }, result)
end

T["Input"]["queues a prompt submitted WHILE a response is in progress"] = function()
  local result = child.lua([[
    write({ "First" })
    chat:submit()
    write({ "Also this" })
    chat:submit()
    write({ "And this" })
    chat:submit()
    return { queued = chat._btw, input = input_lines() }
  ]])

  h.eq("Also this\n\nAnd this", result.queued)
  h.eq({ "" }, result.input)
end

T["Input"]["returns a queued prompt to the input on stop, above what is being written"] = function()
  local result = child.lua([[
    chat.context:add({ id = "<buf>foo.lua</buf>", source = "test" })
    write({ "> Context:", "> - <buf>foo.lua</buf>", "", "First" })
    chat:submit()
    write({ "> Context:", "> - <buf>foo.lua</buf>", "", "Queued" })
    chat:submit()
    write({ "> Context:", "> - <buf>foo.lua</buf>", "", "Still typing" })
    chat:stop()
    return { queued = chat._btw, input = input_lines() }
  ]])

  h.eq(nil, result.queued)
  h.eq({ "> Context:", "> - <buf>foo.lua</buf>", "", "Queued", "", "Still typing" }, result.input)
end

T["Input"]["renders context at the top of the input"] = function()
  local lines = child.lua([[
    write({ "Explain this" })
    chat.context:add({ id = "<buf>foo.lua</buf>", source = "test" })
    chat.context:add({ id = "<buf>bar.lua</buf>", source = "test" })
    return input_lines()
  ]])

  h.eq({ "> Context:", "> - <buf>foo.lua</buf>", "> - <buf>bar.lua</buf>", "", "Explain this" }, lines)
end

T["Input"]["removes context that is deleted from the input"] = function()
  local ids = child.lua([[
    chat.context:add({ id = "<buf>foo.lua</buf>", source = "test" })
    chat.context:add({ id = "<buf>bar.lua</buf>", source = "test" })
    write({ "> Context:", "> - <buf>bar.lua</buf>", "", "Explain this" })
    h.send_to_llm(chat, "Done")
    return vim.tbl_map(function(item)
      return item.id
    end, chat.context_items)
  ]])

  h.eq({ "<buf>bar.lua</buf>" }, ids)
end

T["Input"]["returns a prompt that is prevented from being sent to the input"] = function()
  local result = child.lua([[
    local before = chat_lines()
    chat:add_callback("on_before_submit", function()
      return false
    end)
    write({ "Not yet" })
    chat:submit()
    return { before = before, after = chat_lines(), input = input_lines() }
  ]])

  h.eq(result.before, result.after)
  h.eq({ "Not yet" }, result.input)
end

T["Input"]["adds text from slash commands to the input"] = function()
  local result = child.lua([[
    write({ "The date is" })
    chat:add_to_prompt("today")
    return { chat = chat_lines(), input = input_lines() }
  ]])

  h.eq({ "The date is", "today" }, result.input)
  h.eq(false, vim.tbl_contains(result.chat, "today"))
end

T["Input"]["hides the chat when the input is closed"] = function()
  local visible = child.lua([[
    vim.api.nvim_win_close(input.winnr, true)
    vim.wait(100, function()
      return not chat.ui:is_visible()
    end)
    return chat.ui:is_visible()
  ]])

  h.eq(false, visible)
end

T["Input"]["keeps its height when the chat is hidden and shown again"] = function()
  local height = child.lua([[
    vim.api.nvim_win_set_height(input.winnr, 9)
    chat.ui:hide()
    require("codecompanion.interactions.chat").open({ ui = chat.ui })
    return vim.api.nvim_win_get_height(input.winnr)
  ]])

  h.eq(9, height)
end

T["Input"]["binds approval keymaps in the input until a choice is made"] = function()
  local result = child.lua([[
    local function has_keymap()
      return vim.iter(vim.api.nvim_buf_get_keymap(input.bufnr, "n")):any(function(map)
        return map.lhs == "g1"
      end)
    end

    local on_done = require("codecompanion.interactions.chat.helpers.approval_prompt").request(chat, {
      id = 1,
      choices = { { keymap = "g1", label = "Accept", callback = function() end } },
    })
    local before = has_keymap()
    on_done("Accept")
    return { before = before, after = has_keymap() }
  ]])

  h.eq(true, result.before)
  h.eq(false, result.after)
end

return T
