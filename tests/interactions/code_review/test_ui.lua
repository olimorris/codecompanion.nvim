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

T["UI"]["shows the pending comments for a file, and clears them when the review is sent"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Why 1?", code = "local a = 1", path = "a.txt", start_line = 1, end_line = 1 })
    -- Line 20 doesn't exist, so this one clamps to the last line rather than disappearing
    store.add_comment(repo, { comment = "Outlived\nits code", code = "local z = 9", path = "a.txt", start_line = 20, end_line = 20 })
    store.add_comment(repo, { comment = "Another file", code = "local d = 4", path = "b.txt", start_line = 1, end_line = 1 })

    -- Opening the file after the refresh also covers drawing into a buffer opened mid-review
    ui.refresh()
    bufnr = open("a.txt")

    icon = config.interactions.code_review.display.virtual_text.icon
    expected = { icon .. "Why 1?", icon .. "Outlived", icon .. "its code" }
  ]])

  h.eq(child.lua_get("expected"), child.lua_get("rendered(bufnr)"))

  child.lua([[ui.clear_all()]])
  h.eq({}, child.lua_get("rendered(bufnr)"))
end

T["UI"]["finds the comment on a line after the line has moved"] = function()
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
