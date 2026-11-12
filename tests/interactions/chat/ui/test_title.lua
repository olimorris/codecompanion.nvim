local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.winbar = function(winnr)
          local expression = vim.wo[winnr].winbar
          return vim.api.nvim_eval_statusline(expression, { winid = winnr, use_winbar = true, maxwidth = 80 }).str
        end
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Title"] = new_set()

T["Title"]["shows the title, adapter and model in the winbar"] = function()
  local result = child.lua([[
    _G.chat = h.setup_chat_buffer({ display = { chat = { title = { position = "winbar" } } } })
    local before = winbar(chat.ui.winnr)
    chat:set_title("100% explained")
    return { before = before, after = winbar(chat.ui.winnr) }
  ]])

  h.expect_match(result.before, "^ CodeCompanion.nvim%s+test_adapter · gpt%-3.5%-turbo $")
  h.expect_match(result.after, "^ 100%% explained%s+")
end

T["Title"]["builds the winbar from the chat's metadata with the user's function"] = function()
  local result = child.lua([[
    _G.chat = h.setup_chat_buffer({
      display = {
        chat = {
          title = {
            position = "winbar",
            text = {
              winbar = function(metadata)
                return string.format("%d tokens", metadata.tokens)
              end,
            },
          },
        },
      },
    })
    chat.tokens = 1200
    chat:update_metadata()
    return winbar(chat.ui.winnr)
  ]])

  h.eq("1200 tokens", result)
end

T["Title"]["clears the winbar from a reused window when the chat is hidden"] = function()
  local result = child.lua([[
    _G.chat = h.setup_chat_buffer({ display = { chat = { title = { position = "winbar" }, window = { layout = "buffer" } } } })
    local winnr = chat.ui.winnr
    chat.ui:hide()
    return { shows_chat = vim.api.nvim_win_get_buf(winnr) == chat.bufnr, winbar = vim.wo[winnr].winbar }
  ]])

  h.eq({ shows_chat = false, winbar = "" }, result)
end

T["Title"]["replaces the H1 in place when the title changes"] = function()
  local result = child.lua([[
    _G.chat = h.setup_chat_buffer({ display = { chat = { title = { position = "buffer" } } } })
    local function lines()
      return vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false)
    end
    local before = lines()
    chat:set_title("Explaining the parser")
    return { before = before, after = lines(), winbar = vim.wo[chat.ui.winnr].winbar }
  ]])

  h.eq("# CodeCompanion.nvim", result.before[1])
  h.eq("# Explaining the parser", result.after[1])
  h.eq(#result.before, #result.after)
  h.eq("", result.winbar)
end

T["Title"]["DOES NOT send the H1 to the LLM"] = function()
  local message = child.lua([[
    _G.chat = h.setup_chat_buffer({ display = { chat = { title = { position = "buffer" } } } })
    local last = vim.api.nvim_buf_line_count(chat.bufnr)
    vim.api.nvim_buf_set_lines(chat.bufnr, last, last, false, { "What does this do?" })
    h.send_to_llm(chat, "It does things")
    return chat.messages[#chat.messages - 1].content
  ]])

  h.eq("What does this do?", message)
end

return T
