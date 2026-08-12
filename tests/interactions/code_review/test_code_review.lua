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
        keymaps = require("codecompanion.interactions.code_review.keymaps")
        review = require("codecompanion.interactions.code_review")
        store = require("codecompanion.interactions.code_review.store")

        -- The test config turns code reviews off, so the autocmds this file drives are never registered
        config.interactions.code_review.enabled = true
        review.setup()

        write = function(path, lines)
          vim.fn.writefile(lines, vim.fs.joinpath(repo, path))
        end

        submit = function()
          vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionChatSubmitted" })
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

        -- Put a list of the user's own in the quickfix, so a review taking it over is visible
        own_quickfix = function()
          vim.fn.setqflist({}, " ", { title = "the user's own list", items = { { text = "a hit" } } })
        end

        review_owns_quickfix = function()
          return vim.fn.getqflist({ title = 0 }).title == "CodeCompanion Code Review"
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

        -- Every case shares one quickfix buffer, so release any maps the last one left on it
        keymaps.restore()

        -- Free the whole stack, so a case that never reaches `setqflist` can't read the last one's list
        vim.fn.setqflist({}, "f")

        -- One case swaps in a provider of its own, which would otherwise stand for the rest of them
        config.interactions.code_review.display.diff.provider = "native"

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

T["Review"]["comment on a file in a subdirectory stores a root-relative path"] = function()
  child.lua([[
    stub_input("Nested file comment")
    vim.fn.mkdir(vim.fs.joinpath(repo, "src"), "p")
    -- cd into the subdir so cwd is not the git root
    vim.cmd.cd(vim.fs.joinpath(repo, "src"))
    vim.cmd("edit! notes")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    review.comment({ range = 0 })
  ]])

  local pending = child.lua_get("review.pending()")
  h.eq(1, #pending)
  h.eq("src/notes", pending[1].path)
end

T["Review"]["editing a comment to empty removes it"] = function()
  child.lua([[
    stub_input("First pass")
    vim.cmd("edit! notes")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line one" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    review.comment({ range = 0 })

    -- Second call on the same line hits edit_comment; empty submit deletes it
    stub_input("")
    review.comment({ range = 0 })
  ]])

  h.eq(0, child.lua_get("#review.pending()"))
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
end

T["Review"]["share does nothing when there are no comments"] = function()
  child.lua([[review.share()]])

  h.eq(vim.NIL, child.lua_get("baseline.get(repo)"))
  h.is_false(child.lua_get([[require("codecompanion.utils.files").exists(store.review_path(repo))]]))
end

T["Review"]["approve sets a baseline when none exists"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    review.approve()
  ]])

  h.expect_match(child.lua_get("baseline.get(repo)"), "^%x+$")
  h.eq(0, child.lua_get("#baseline.diff(repo)"))
end

T["Review"]["approve advances the baseline but keeps pending comments"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Still pending", code = "local a", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })
    review.approve()
  ]])

  h.eq(1, child.lua_get("#review.pending()"))
  h.expect_match(child.lua_get("baseline.get(repo)"), "^%x+$")
end

T["Review"]["open leaves the quickfix alone when there is no baseline"] = function()
  child.lua([[
    own_quickfix()
    review.open()
  ]])

  h.is_false(child.lua_get("review_owns_quickfix()"))
end

T["Review"]["open leaves the quickfix alone when the agent has not edited anything"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    own_quickfix()
    review.open()
  ]])

  h.is_false(child.lua_get("review_owns_quickfix()"))
end

T["Review"]["open leaves the quickfix alone when the worktree can't be read"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 100" })

    -- A lock another Neovim holds, so the diff can't be trusted and must not be read as "no edits"
    local index = vim.fs.joinpath(
      vim.trim(vim.system({ "git", "-C", repo, "rev-parse", "--absolute-git-dir" }, { text = true }):wait().stdout),
      "codecompanion-index"
    )
    vim.fn.writefile({}, index .. ".lock")

    own_quickfix()
    review.open()
  ]])

  h.is_false(child.lua_get("review_owns_quickfix()"))
end

T["Review"]["open lists a quickfix entry per hunk in the agent's files"] = function()
  child.lua([[
    write("a.lua", { "local a = 1", "local b = 2", "local c = 3" })
    write("b.lua", { "local d = 4" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 1", "local b = 20", "local c = 3" })
    write("b.lua", { "local d = 40" }) -- the user's own edit, not the agent's

    own_quickfix()
    review.open()
  ]])

  local qf = child.lua_get("vim.fn.getqflist()")
  h.eq(1, #qf)
  h.eq(2, qf[1].lnum)
  h.is_true(child.lua_get("vim.endswith(vim.fn.bufname(vim.fn.getqflist()[1].bufnr), 'a.lua')"))
  -- Anchors the cases asserting a review *didn't* take the quickfix over
  h.is_true(child.lua_get("review_owns_quickfix()"))
end

T["Review"]["a new round re-baselines, so only the agent's edits are left to review"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    write("b.lua", { "local b = 2" })
    submit()

    -- A pull brings work of its own, and the user edits a file by hand
    write("a.lua", { "local a = 1", "-- from upstream" })
    write("b.lua", { "local b = 2", "-- typed by hand" })
    submit()

    -- Only now does the agent edit anything
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 1", "-- from upstream", "-- from the agent" })

    -- Scoped to everything, so nothing is merely being filtered out by file
    review.open({ scope = "all" })
  ]])

  h.eq(1, child.lua_get("#vim.fn.getqflist()"))
  h.eq("+1 -0 -- from the agent", child.lua_get("vim.fn.getqflist()[1].text"))
end

T["Review"]["a round still to be reviewed keeps its baseline"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    before = baseline.get(repo)
    write("a.lua", { "local a = 10" })

    -- An edit the user hasn't reviewed yet
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    submit()
    after_edit = baseline.get(repo)

    -- A comment they haven't sent yet
    store.clear_edited(repo)
    store.add_comment(repo, { comment = "Why 10?", code = "local a = 10", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })
    submit()
    after_comment = baseline.get(repo)
  ]])

  h.eq(child.lua_get("before"), child.lua_get("after_edit"))
  h.eq(child.lua_get("before"), child.lua_get("after_comment"))
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

T["Review"]["accept keeps the hunk out of later reviews, until the baseline advances"] = function()
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

  child.lua([[review.open({ scope = "all" })]])
  h.eq(2, child.lua_get("#vim.fn.getqflist()"))

  child.lua([[review.approve()]])
  h.is_true(child.lua_get("next(store.accepted(repo)) == nil"))
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

T["Review"]["accept does nothing without a review entry"] = function()
  child.lua([[
    vim.fn.setqflist({}, " ", { items = {} })
    review.accept()
  ]])

  h.is_true(child.lua_get("next(store.accepted(repo)) == nil"))
end

T["Review"]["ignore drops every hunk in the file, until the baseline advances"] = function()
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

  child.lua([[review.approve()]])
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

T["Review"]["accepting or ignoring a hunk closes the diff it was being read in"] = function()
  child.lua([[
    in_diff_mode = function()
      return #vim.tbl_filter(function(win)
        return vim.wo[win].diff
      end, vim.api.nvim_list_wins())
    end

    -- An extension-less name keeps filetype plugins out of the test
    write("notes", { "local a = 1" })
    write("other", { "local b = 2" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "notes"))
    store.track(repo, vim.fs.joinpath(repo, "other"))
    write("notes", { "local a = 10" })
    write("other", { "local b = 20" })

    review.open()
    review.open_diff()
    opened = in_diff_mode()

    review.accept()
    after_accept = in_diff_mode()

    review.open_diff()
    review.ignore()
    after_ignore = in_diff_mode()
  ]])

  h.eq(2, child.lua_get("opened"))
  h.eq(0, child.lua_get("after_accept"))
  h.eq(0, child.lua_get("after_ignore"))
end

T["Review"]["open_diff hands the hunk under the cursor to the configured provider"] = function()
  child.lua([[
    -- NOTE: Why is this so tightly coupled to the config?!
    config.interactions.code_review.display.diff.provider = function(target)
      captured = target
    end
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 10" })

    review.open()
    review.open_diff()
  ]])

  h.eq("a.lua", child.lua_get("captured.path"))
  h.eq(1, child.lua_get("captured.line"))
  h.eq(child.lua_get("baseline.alias()"), child.lua_get("captured.baseline_ref"))
  h.is_true(child.lua_get("captured.id ~= nil"))
end

T["Review"]["the review keymaps take the quickfix window, and give it back to another list"] = function()
  child.lua([[
    -- Which keys are bound is the user's business, so the whole test drives off the config
    review_keymaps = function()
      local descriptions = vim.tbl_map(function(map)
        return map.desc
      end, vim.api.nvim_buf_get_keymap(0, "n"))

      local found = {}
      for name, keymap in pairs(config.interactions.code_review.keymaps) do
        if vim.list_contains(descriptions, keymap.description) then
          table.insert(found, name)
        end
      end
      table.sort(found)
      return found
    end

    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.track(repo, vim.fs.joinpath(repo, "a.lua"))
    write("a.lua", { "local a = 10" })

    all_keymaps = vim.tbl_keys(config.interactions.code_review.keymaps)
    table.sort(all_keymaps)

    accept_key = config.interactions.code_review.keymaps.accept.modes.n
    vim.cmd.copen()
    vim.keymap.set("n", accept_key, "j", { buffer = 0, desc = "the user's own map" })

    review.open()
    during_review = review_keymaps()

    vim.fn.setqflist({}, " ", { title = "grep", items = { { text = "hit" } } })
  ]])

  h.eq(child.lua_get("all_keymaps"), child.lua_get("during_review"))

  -- The review's own key, pressed on a list it doesn't own, hands the window back
  child.type_keys(child.lua_get("accept_key"))

  child.lua([[
    after_takeover = review_keymaps()
    user_map = vim.iter(vim.api.nvim_buf_get_keymap(0, "n")):find(function(map)
      return map.lhs == accept_key
    end)
  ]])

  h.eq({}, child.lua_get("after_takeover"))
  h.eq("the user's own map", child.lua_get("user_map.desc"))
  h.eq(0, child.lua_get("#notifications"))
end

return T
