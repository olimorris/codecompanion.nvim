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

        baseline = require("codecompanion.interactions.code_review.baseline")
        config = require("codecompanion.config")
        review = require("codecompanion.interactions.code_review")
        store = require("codecompanion.interactions.code_review.store")

        write = function(path, lines)
          vim.fn.writefile(lines, vim.fs.joinpath(repo, path))
        end

        commit = function(message)
          vim.system({ "git", "-C", repo, "-c", "user.name=Test", "-c", "user.email=test@test", "commit", "--quiet", "--allow-empty", "-m", message }):wait()
        end

        checkout = function(...)
          vim.system({ "git", "-C", repo, "checkout", "--quiet", ... }):wait()
        end

        -- Stub the input popup so `comment` submits immediately
        stub_input = function(comment)
          package.loaded["codecompanion.interactions.shared.input"].open = function(opts)
            opts.on_submit(comment)
          end
        end

        package.loaded["codecompanion.utils"].notify = function(message)
          table.insert(notifications, message)
        end
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

        notifications = {}
      ]])
    end,
    post_once = child.stop,
  },
})

T["Review"] = new_set()

T["Review"]["comment stores the current line with the typed comment"] = function()
  child.lua([[
    stub_input("Handle the nil case")
    -- An extension-less name keeps filetype plugins out of the test
    vim.cmd("edit! notes")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line one", "line two", "line three" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    review.comment({ range = 0 })
  ]])

  local pending = child.lua_get("review.pending()")
  h.eq(1, #pending)
  h.eq("Handle the nil case", pending[1].comment)
  h.eq("line two", pending[1].code)
  h.eq("notes", pending[1].path)
  h.eq(2, pending[1].start_line)
  h.eq(2, pending[1].end_line)
end

T["Review"]["comment stores a visual selection"] = function()
  child.lua([[
    stub_input("Rename these")
    vim.cmd("edit! notes")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line one", "line two", "line three" })
    vim.api.nvim_buf_set_mark(buf, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 2, 10, {})

    review.comment({ range = 2 })
  ]])

  local pending = child.lua_get("review.pending()")
  h.eq(1, #pending)
  h.eq("Rename these", pending[1].comment)
  h.eq("line one\nline two", pending[1].code)
  h.eq(1, pending[1].start_line)
  h.eq(2, pending[1].end_line)
end

T["Review"]["comment does nothing when sending code is disabled"] = function()
  child.lua([[
    stub_input("Should not be added")
    config.opts.send_code = false

    review.comment({ range = 0 })

    config.opts.send_code = true
  ]])

  h.eq(0, child.lua_get("#review.pending()"))
end

T["Review"]["consume drains the comments and advances the baseline"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 100" })
    store.add_comment(repo, { comment = "Why 100?", code = "local a = 100", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })

    consumed = review.consume()
  ]])

  h.eq(1, child.lua_get("#consumed"))
  h.eq("Why 100?", child.lua_get("consumed[1].comment"))
  h.eq(0, child.lua_get("#review.pending()"))
  h.eq(0, child.lua_get("#store.edited(repo)"))
  h.eq(0, child.lua_get("#baseline.diff(repo)")) -- The commented change is now part of the baseline, so nothing is left to review
end

T["Review"]["consume returns nil when there are no comments"] = function()
  h.eq(vim.NIL, child.lua_get("review.consume()"))
end

T["Review"]["share moves the comments to the review file and advances the baseline"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 100" })
    store.add_comment(repo, { comment = "Why 100?", code = "local a = 100", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })

    review.share()
  ]])

  h.eq(0, child.lua_get("#review.pending()"))
  h.eq(0, child.lua_get("#baseline.diff(repo)"))
  h.is_true(child.lua_get([[require("codecompanion.utils.files").exists(store.review_path(repo))]]))
  h.expect_contains("Why 100?", child.lua_get([[require("codecompanion.utils.files").read(store.review_path(repo))]]))
  h.expect_contains(child.lua_get("store.review_path(repo)"), child.lua_get("notifications[1]"))
end

T["Review"]["share warns when there are no comments"] = function()
  child.lua([[review.share()]])

  h.eq("No comments to share", child.lua_get("notifications[1]"))
  h.eq(vim.NIL, child.lua_get("baseline.get(repo)"))
end

T["Review"]["approve sets a baseline when none exists"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    review.approve()
  ]])

  h.expect_match(child.lua_get("baseline.get(repo)"), "^%x+$")
  h.eq(0, child.lua_get("#baseline.diff(repo)"))
end

T["Review"]["approve keeps pending comments and warns"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Still pending", code = "local a", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })
    review.approve()
  ]])

  h.eq(1, child.lua_get("#review.pending()"))
  h.expect_contains("pending comment", child.lua_get("notifications[1]"))
end

T["Review"]["open warns when there is no baseline"] = function()
  child.lua([[review.open()]])

  h.eq("No edits to review yet", child.lua_get("notifications[1]"))
end

T["Review"]["open warns when the agent has not edited anything"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    review.open()
  ]])

  h.expect_contains("No edits to review", child.lua_get("notifications[1]"))
end

T["Review"]["open lists a quickfix entry per hunk in the agent's files"] = function()
  child.lua([[
    write("a.lua", { "local a = 1", "local b = 2", "local c = 3" })
    write("b.lua", { "local d = 4" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 1", "local b = 20", "local c = 3" })
    write("b.lua", { "local d = 40" }) -- the user's own edit, not the agent's

    review.open()
  ]])

  local qf = child.lua_get("vim.fn.getqflist()")
  h.eq(1, #qf)
  h.eq(2, qf[1].lnum)
  h.is_true(child.lua_get("vim.endswith(vim.fn.bufname(vim.fn.getqflist()[1].bufnr), 'a.lua')"))
end

T["Review"]["open with scope all includes changes outside the agent's files"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    write("b.lua", { "local b = 2" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 10" })
    write("b.lua", { "local b = 20" })

    review.open({ scope = "all" })
  ]])

  h.eq(2, child.lua_get("#vim.fn.getqflist()"))
end

T["Review"]["accept keeps the hunk out of future reviews"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    write("b.lua", { "local b = 2" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    store.track(repo, vim.fs.joinpath(repo, "b.lua"))
    write("a.lua", { "local a = 10" })
    write("b.lua", { "local b = 20" })

    -- open leaves the cursor in the quickfix window, on the a.lua hunk
    review.open()
    review.accept()
  ]])

  h.eq(1, child.lua_get("#vim.fn.getqflist()"))

  child.lua([[review.open()]])
  h.eq(1, child.lua_get("#vim.fn.getqflist()"))
  h.is_true(child.lua_get("vim.endswith(vim.fn.bufname(vim.fn.getqflist()[1].bufnr), 'b.lua')"))
end

T["Review"]["an accepted hunk returns when the change changes"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 10" })

    review.open()
    review.accept()
    write("a.lua", { "local a = 100" })
    review.open()
  ]])

  h.eq(1, child.lua_get("#vim.fn.getqflist()"))
end

T["Review"]["open with scope all includes accepted hunks"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 10" })

    review.open()
    review.accept()
    review.open({ scope = "all" })
  ]])

  h.eq(1, child.lua_get("#vim.fn.getqflist()"))
end

T["Review"]["advancing the baseline forgets the accepted hunks"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 10" })

    review.open()
    review.accept()
    review.approve()
  ]])

  h.is_true(child.lua_get("next(store.accepted(repo)) == nil"))
end

T["Review"]["accept warns without a review entry"] = function()
  child.lua([[
    vim.fn.setqflist({}, " ", { items = {} })
    review.accept()
  ]])

  h.eq("No review hunk under the cursor", child.lua_get("notifications[1]"))
end

T["Review"]["ignore drops every hunk in the file until the baseline advances"] = function()
  child.lua([[
    write("a.lua", { "local a = 1", "local b = 2", "local c = 3" })
    write("b.lua", { "local d = 4" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    store.track(repo, vim.fs.joinpath(repo, "b.lua"))
    write("a.lua", { "local a = 10", "local b = 2", "local c = 30" })
    write("b.lua", { "local d = 40" })

    -- open leaves the cursor in the quickfix window, on the first a.lua hunk
    review.open()
    review.ignore()
  ]])

  h.eq(1, child.lua_get("#vim.fn.getqflist()"))

  child.lua([[review.open()]])
  h.eq(1, child.lua_get("#vim.fn.getqflist()"))
  h.is_true(child.lua_get("vim.endswith(vim.fn.bufname(vim.fn.getqflist()[1].bufnr), 'b.lua')"))

  child.lua([[review.open({ scope = "all" })]])
  h.eq(3, child.lua_get("#vim.fn.getqflist()"))
end

T["Review"]["advancing the baseline forgets the ignored files"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 10" })

    review.open()
    review.ignore()
    review.approve()
  ]])

  h.is_true(child.lua_get("next(store.ignored(repo)) == nil"))
end

T["Review"]["comment from the quickfix list targets the hunk"] = function()
  child.lua([[
    stub_input("Why 10?")
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 10" })

    review.open()
    review.comment()
  ]])

  local pending = child.lua_get("review.pending()")
  h.eq(1, #pending)
  h.eq("Why 10?", pending[1].comment)
  h.eq("a.lua", pending[1].path)
  h.eq("local a = 10", pending[1].code)
  h.eq(1, pending[1].start_line)
  h.eq(1, pending[1].end_line)
end

T["Review"]["open sets the review keymaps in the quickfix window"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 10" })

    review.open()
    mapped = vim.tbl_map(function(map)
      return map.lhs
    end, vim.api.nvim_buf_get_keymap(0, "n"))
  ]])

  h.is_true(child.lua_get([[vim.list_contains(mapped, "a")]]))
  h.is_true(child.lua_get([[vim.list_contains(mapped, "c")]]))
  h.is_true(child.lua_get([[vim.list_contains(mapped, "x")]]))
end

T["Review"]["keymaps release when another list takes over the quickfix"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 10" })

    review.open()
    vim.fn.setqflist({}, " ", { title = "grep", items = { { text = "hit" } } })
  ]])

  child.type_keys("a")

  child.lua([[
    mapped = vim.tbl_map(function(map)
      return map.lhs
    end, vim.api.nvim_buf_get_keymap(0, "n"))
  ]])
  h.is_true(child.lua_get([[not vim.list_contains(mapped, "a")]]))
  h.is_true(child.lua_get([[not vim.list_contains(mapped, "c")]]))
  h.eq(0, child.lua_get("#notifications"))
end

T["Review"]["keymaps restore the mapping they replaced"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 10" })

    vim.cmd.copen()
    vim.keymap.set("n", "a", "j", { buffer = 0, desc = "the user's own map" })
    review.open()
    vim.fn.setqflist({}, " ", { title = "grep", items = { { text = "hit" } } })
  ]])

  child.type_keys("a")

  child.lua([[
    user_map = vim.iter(vim.api.nvim_buf_get_keymap(0, "n")):find(function(map)
      return map.lhs == "a"
    end)
  ]])
  h.eq("the user's own map", child.lua_get("user_map.desc"))
end

return T
