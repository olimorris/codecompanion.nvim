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
        store = require("codecompanion.interactions.code_review.store")
        ui = require("codecompanion.interactions.code_review.ui")

        -- The virtual lines a buffer is showing, one string per line
        rendered = function(bufnr)
          local lines = {}
          for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, -1, 0, -1, { details = true })) do
            for _, virt_line in ipairs(mark[4].virt_lines or {}) do
              table.insert(lines, virt_line[1][1])
            end
          end
          return lines
        end

        open = function(path)
          vim.cmd.edit(vim.fs.joinpath(repo, path))
          return vim.api.nvim_get_current_buf()
        end
      ]])
    end,
    pre_case = function()
      child.lua([[
        config.interactions.code_review.opts.storage_dir = vim.fn.tempname()
        config.interactions.code_review.display.virtual_text.enabled = true

        repo = vim.fn.tempname()
        vim.fn.mkdir(repo, "p")
        repo = vim.uv.fs_realpath(repo)
        vim.system({ "git", "-C", repo, "init", "--quiet" }):wait()
        vim.cmd.cd(repo)
        vim.fn.writefile({ "local a = 1", "local b = 2", "local c = 3" }, vim.fs.joinpath(repo, "a.txt"))
      ]])
    end,
    post_once = child.stop,
  },
})

T["UI"] = new_set()

T["UI"]["renders a comment above the line it was written against"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Why 1?", code = "local a = 1", path = "a.txt", start_line = 1, end_line = 1 })
    bufnr = open("a.txt")
    ui.render(bufnr)
  ]])

  h.eq({ "💬 Why 1?" }, child.lua_get("rendered(bufnr)"))
end

T["UI"]["renders each line of a multi-line comment"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Why 1?\nExplain", code = "local a = 1", path = "a.txt", start_line = 1, end_line = 1 })
    bufnr = open("a.txt")
    ui.render(bufnr)
  ]])

  h.eq({ "💬 Why 1?", "💬 Explain" }, child.lua_get("rendered(bufnr)"))
end

T["UI"]["renders nothing for a file with no comments"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Why 1?", code = "local a = 1", path = "b.txt", start_line = 1, end_line = 1 })
    bufnr = open("a.txt")
    ui.render(bufnr)
  ]])

  h.eq({}, child.lua_get("rendered(bufnr)"))
end

T["UI"]["renders nothing when virtual text is turned off"] = function()
  child.lua([[
    config.interactions.code_review.display.virtual_text.enabled = false
    store.add_comment(repo, { comment = "Why 1?", code = "local a = 1", path = "a.txt", start_line = 1, end_line = 1 })
    bufnr = open("a.txt")
    ui.render(bufnr)
  ]])

  h.eq({}, child.lua_get("rendered(bufnr)"))
end

T["UI"]["keeps a comment in view when its line no longer exists"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Gone", code = "local z = 9", path = "a.txt", start_line = 20, end_line = 20 })
    bufnr = open("a.txt")
    ui.render(bufnr)
  ]])

  h.eq({ "💬 Gone" }, child.lua_get("rendered(bufnr)"))
end

T["UI"]["clear_all removes the comments from every buffer"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Why 1?", code = "local a = 1", path = "a.txt", start_line = 1, end_line = 1 })
    bufnr = open("a.txt")
    ui.render(bufnr)
    ui.clear_all()
  ]])

  h.eq({}, child.lua_get("rendered(bufnr)"))
end

T["UI"]["watches for files being opened only while comments are pending"] = function()
  child.lua([[
    watchers = function()
      return #vim.api.nvim_get_autocmds({ event = "BufReadPost" })
    end

    ui.refresh()
    without_comments = watchers()

    store.add_comment(repo, { comment = "Why 1?", code = "local a = 1", path = "a.txt", start_line = 1, end_line = 1 })
    ui.refresh()
    with_comments = watchers()

    ui.clear_all()
    after_clearing = watchers()
  ]])

  h.eq(child.lua_get("without_comments") + 1, child.lua_get("with_comments"))
  h.eq(child.lua_get("without_comments"), child.lua_get("after_clearing"))
end

T["UI"]["draws a comment into a file opened while comments are pending"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Why 1?", code = "local a = 1", path = "a.txt", start_line = 1, end_line = 1 })
    ui.refresh()

    bufnr = open("a.txt")
  ]])

  h.eq({ "💬 Why 1?" }, child.lua_get("rendered(bufnr)"))
end

T["UI"]["comment_at finds the comment on a line"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Why 2?", code = "local b = 2", path = "a.txt", start_line = 2, end_line = 2 })
    bufnr = open("a.txt")
    ui.render(bufnr)
  ]])

  h.eq("Why 2?", child.lua_get("ui.comment_at(bufnr, 2).comment.comment"))
  h.eq(vim.NIL, child.lua_get("ui.comment_at(bufnr, 1)"))
end

T["UI"]["comment_at follows a line that has moved"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Why 2?", code = "local b = 2", path = "a.txt", start_line = 2, end_line = 2 })
    bufnr = open("a.txt")
    ui.render(bufnr)

    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "-- a new line on top" })
  ]])

  h.eq(vim.NIL, child.lua_get("ui.comment_at(bufnr, 2)"))
  h.eq("Why 2?", child.lua_get("ui.comment_at(bufnr, 3).comment.comment"))
end

return T
