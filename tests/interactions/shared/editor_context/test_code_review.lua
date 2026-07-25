local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
local new_set = MiniTest.new_set

T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        h.setup_plugin()

        config = require("codecompanion.config")
        review = require("codecompanion.interactions.code_review")
        store = require("codecompanion.interactions.code_review.store")
      ]])
    end,
    pre_case = function()
      -- A fresh repo and storage directory per case; the child itself is only started once
      child.lua([[
        storage_dir = vim.fn.tempname()
        config.interactions.code_review.opts.storage_dir = storage_dir

        repo = vim.fn.tempname()
        vim.fn.mkdir(repo, "p")
        repo = vim.uv.fs_realpath(repo)
        vim.system({ "git", "-C", repo, "init", "--quiet" }):wait()
        vim.cmd.cd(repo)
      ]])
    end,
    post_once = child.stop,
  },
})

T["Editor context"] = new_set()

T["Editor context"]["chat_render adds a hidden message and drains the comments"] = function()
  child.lua([[
    chat = h.setup_chat_buffer()
    -- setup_chat_buffer replaces the config, so point storage back at this test's directory
    config.interactions.code_review.opts.storage_dir = storage_dir
    store.add_comment(repo, { comment = "Handle the nil case", code = "local x = 1", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })

    require("codecompanion.interactions.shared.editor_context.code_review").new({ Chat = chat }):chat_render()
  ]])

  local message = child.lua_get("chat.messages[#chat.messages]")
  h.expect_starts_with("Here are the comments from my code review:", message.content)
  h.expect_contains('<comment file="a.lua" lines="1-1">', message.content)
  h.expect_contains("Handle the nil case", message.content)
  h.eq(false, message.opts.visible)
  h.eq("review", message._meta.tag)
  h.eq(0, child.lua_get("#review.pending()"))
end

T["Editor context"]["chat_render writes the comments into the chat buffer for the user to read"] = function()
  child.lua([[
    chat = h.setup_chat_buffer()
    config.interactions.code_review.opts.storage_dir = storage_dir
    store.add_comment(repo, { comment = "Handle the nil case", code = "local x = 1", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })
    store.add_comment(repo, { comment = "Rename these", code = "local y = 2", filetype = "lua", path = "b.lua", start_line = 4, end_line = 6 })

    require("codecompanion.interactions.shared.editor_context.code_review").new({ Chat = chat }):chat_render()
    buffer = table.concat(vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), "\n")
  ]])

  local buffer = child.lua_get("buffer")
  h.expect_contains("````markdown", buffer)
  h.expect_contains("a.lua:1\nHandle the nil case", buffer)
  h.expect_contains("b.lua:4-6\nRename these", buffer)
end

T["Editor context"]["chat_render adds nothing when there are no comments"] = function()
  child.lua([[
    chat = h.setup_chat_buffer()
    config.interactions.code_review.opts.storage_dir = storage_dir
    message_count = #chat.messages

    require("codecompanion.interactions.shared.editor_context.code_review").new({ Chat = chat }):chat_render()
  ]])

  h.eq(child.lua_get("message_count"), child.lua_get("#chat.messages"))
end

T["Editor context"]["replace swaps the tag for a phrase that reads as English"] = function()
  local replaced = child.lua_get([[
    require("codecompanion.interactions.shared.editor_context.code_review").replace("#", "Can you action #{code_review}?")
  ]])

  h.eq("Can you action my comments from the code review, which I've attached?", replaced)
end

T["Editor context"]["a chat message tagged with #{code_review} carries the comments to the LLM"] = function()
  child.lua([[
    chat = h.setup_chat_buffer()
    config.interactions.code_review.opts.storage_dir = storage_dir
    store.add_comment(repo, { comment = "Handle the nil case", code = "local x = 1", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })

    message = { role = "user", content = "Can you action #{code_review}?" }
    chat:replace_user_inputs(message)
  ]])

  h.eq("Can you action my comments from the code review, which I've attached?", child.lua_get("message.content"))
  h.expect_contains("Handle the nil case", child.lua_get("chat.messages[#chat.messages].content"))
  h.eq(0, child.lua_get("#review.pending()"))
end

T["Editor context"]["cli_render returns the formatted block and drains the comments"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Handle the nil case", code = "local x = 1", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })

    rendered = require("codecompanion.interactions.shared.editor_context.code_review").new({}):cli_render()
  ]])

  h.eq("code review comments", child.lua_get("rendered.inline"))
  h.expect_contains("Handle the nil case", child.lua_get("rendered.block"))
  h.eq(0, child.lua_get("#review.pending()"))
end

T["Editor context"]["cli_render returns nil when there are no comments"] = function()
  h.eq(
    vim.NIL,
    child.lua_get([[require("codecompanion.interactions.shared.editor_context.code_review").new({}):cli_render()]])
  )
end

return T
