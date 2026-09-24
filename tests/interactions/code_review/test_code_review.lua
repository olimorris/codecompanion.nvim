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

        -- The test config turns code reviews off, so the autocmds this file drives are never registered
        config.interactions.code_review.enabled = true
        review.setup()

        write = function(path, lines)
          vim.fn.writefile(lines, vim.fs.joinpath(repo, path))
        end

        submit = function()
          vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionChatSubmitted" })
        end

        done = function()
          vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionChatDone" })
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
    submit()
    write("a.lua", { "local a = 100" })
    store.add_comment(repo, { comment = "Why 100?", code = "local a = 100", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })

    consumed = review.consume()
  ]])

  h.eq(1, child.lua_get("#consumed"))
  h.eq("Why 100?", child.lua_get("consumed[1].comment"))
  h.eq(0, child.lua_get("#review.pending()"))
  h.is_false(child.lua_get("store.round_open(repo)"))
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

T["Review"]["closing a round off sets a baseline when none exists"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    review.mark_reviewed()
  ]])

  h.expect_match(child.lua_get("baseline.get(repo)"), "^%x+$")
  h.eq(0, child.lua_get("#baseline.diff(repo)"))
end

T["Review"]["closing a round off forgets the comments sent before it"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    store.write_sent(repo, { { path = "a.lua", start_line = 1, end_line = 1, code = "", comment = "Rename it" } })
    review.mark_reviewed()
  ]])

  h.eq(0, child.lua_get("#store.sent(repo)"))
end

T["Review"]["closing a round off forgets the explanations given during it"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    store.add_explanation(repo, { path = "a.lua", start_line = 1, end_line = 1, code = "", comment = "Sets a" })
    review.mark_reviewed()
  ]])

  h.eq(0, child.lua_get("#store.explanations(repo)"))
end

T["Review"]["a submitted chat becomes the round's channel"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionChatSubmitted", data = { bufnr = 42, id = 7 } })
  ]])

  h.eq({ kind = "chat", bufnr = 42 }, child.lua_get("store.round_channel(repo)"))

  child.lua("review.mark_reviewed()")
  h.eq(vim.NIL, child.lua_get("store.round_channel(repo)"))
end

T["Review"]["closing a round off keeps pending comments"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "Still pending", code = "local a", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })
    review.mark_reviewed()
  ]])

  h.eq(1, child.lua_get("#review.pending()"))
  h.expect_match(child.lua_get("baseline.get(repo)"), "^%x+$")
end

T["Review"]["the first submission after a review re-baselines, dropping the user's own work"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    submit()
    write("a.lua", { "local a = 1", "-- from the agent" })
    review.mark_reviewed()

    -- A pull brings work of its own, and the user edits a file by hand
    write("b.lua", { "-- from upstream" })
    write("a.lua", { "local a = 1", "-- from the agent", "-- typed by hand" })
    submit()

    write("a.lua", { "local a = 1", "-- from the agent", "-- typed by hand", "-- from the next round" })
    hunks = baseline.diff(repo)
  ]])

  h.eq(1, child.lua_get("#hunks"))
  h.eq("+1 -0 -- from the next round", child.lua_get("hunks[1].summary"))
end

T["Review"]["a round the agent changed nothing in closes, so the next one re-baselines"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    submit()

    -- The agent only answered a question, so there is nothing to hold the baseline for
    done()
    closed = store.round_open(repo)

    -- A pull brings work of its own, and the user edits a file by hand
    write("b.lua", { "-- from upstream" })
    write("a.lua", { "local a = 1", "-- typed by hand" })
    submit()

    write("a.lua", { "local a = 1", "-- typed by hand", "-- from the agent" })
    hunks = baseline.diff(repo)
  ]])

  h.is_false(child.lua_get("closed"))
  h.eq(1, child.lua_get("#hunks"))
  h.eq("+1 -0 -- from the agent", child.lua_get("hunks[1].summary"))
end

T["Review"]["a round the agent edited in stays open"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    submit()
    write("a.lua", { "local a = 10" })
    done()
  ]])

  h.is_true(child.lua_get("store.round_open(repo)"))
end

T["Review"]["a round still to be reviewed keeps its baseline"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    submit()
    before = baseline.get(repo)

    -- An edit the user hasn't reviewed yet
    write("a.lua", { "local a = 10" })
    submit()
    after_edit = baseline.get(repo)

    review.mark_reviewed()
    reviewed = baseline.get(repo)

    -- A comment they haven't sent yet
    store.add_comment(repo, { comment = "Why 10?", code = "local a = 10", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })
    submit()
    after_comment = baseline.get(repo)
  ]])

  h.eq(child.lua_get("before"), child.lua_get("after_edit"))
  h.eq(child.lua_get("reviewed"), child.lua_get("after_comment"))
end

return T
