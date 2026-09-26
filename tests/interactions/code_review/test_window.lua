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
        window = require("codecompanion.interactions.code_review.window")

        git = function(...)
          vim.system({ "git", "-C", repo, "-c", "user.name=Test", "-c", "user.email=test@test", ... }):wait()
        end

        focus_pane_row = function(row)
          vim.api.nvim_set_current_win(vim.fn.bufwinid(vim.fn.bufnr("Code Review Diff")))
          vim.api.nvim_win_set_cursor(0, { row, 0 })
        end

        write = function(path, lines)
          vim.fn.writefile(lines, vim.fs.joinpath(repo, path))
        end

        read = function(path)
          return vim.fn.readfile(vim.fs.joinpath(repo, path))
        end

        get_rows = function()
          return vim.api.nvim_buf_get_lines(vim.fn.bufnr("Code Review"), 0, -1, false)
        end

        -- Two changes in separate functions, so each is its own row
        write_two_rows = function()
          write("a.lua", { "local function first()", "  return 1", "end", "local function second()", "  return 2", "end" })
          baseline.snapshot(repo)
          write("a.lua", { "local function first()", "  return 10", "end", "local function second()", "  return 20", "end" })
        end

        package.loaded["codecompanion.utils"].notify = function(message)
          table.insert(notifications, message)
        end
      ]])
    end,
    pre_case = function()
      child.lua([[
        window.close()
        vim.cmd("silent! %bwipeout!")

        storage_dir = vim.fn.tempname()
        config.interactions.code_review.opts.storage_dir = storage_dir
        config.interactions.code_review.opts.auto_accept = {}

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

T["Window"] = new_set()

T["Window"]["accepting a row takes it off the list and leaves the file alone"] = function()
  child.lua("write_two_rows(); window.open()")
  child.type_keys("j", "ga")

  h.eq({ "1 file, 1 hunk", "a.lua  +1 -1", "  +1 -1  in second" }, child.lua_get("get_rows()"))
  h.eq("  return 10", child.lua_get("read('a.lua')[2]"))
end

T["Window"]["accepting a file row clears every row in the file"] = function()
  child.lua("write_two_rows(); window.open()")
  child.type_keys("ga")

  h.eq({ "No edits left to review" }, child.lua_get("get_rows()"))
end

T["Window"]["undoing an accept brings the row back"] = function()
  child.lua("write_two_rows(); window.open()")
  child.type_keys("j", "ga", "u")

  h.eq({ "1 file, 2 hunks", "a.lua  +2 -2", "  +1 -1  in first", "  +1 -1  in second" }, child.lua_get("get_rows()"))
end

T["Window"]["reverting a row puts the baseline lines back in the file"] = function()
  child.lua("write_two_rows(); window.open()")
  child.type_keys("j", "gr")

  h.eq({ "1 file, 1 hunk", "a.lua  +1 -1", "  +1 -1  in second" }, child.lua_get("get_rows()"))
  h.eq("  return 1", child.lua_get("read('a.lua')[2]"))
  h.eq("  return 20", child.lua_get("read('a.lua')[5]"))
end

T["Window"]["DOES NOT revert a file with unsaved changes"] = function()
  child.lua([[
    write_two_rows()
    local bufnr = vim.fn.bufadd(vim.fs.joinpath(repo, "a.lua"))
    vim.fn.bufload(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "-- typed but not saved" })
    window.open()
  ]])
  child.type_keys("j", "gr")

  h.eq("  return 10", child.lua_get("read('a.lua')[2]"))
  h.eq({ "`a.lua` has unsaved changes" }, child.lua_get("notifications"))
end

T["Window"]["reverting a grouped row restores every hunk in it, and undo puts them all back"] = function()
  child.lua([[
    local body = { "local M = {}", "", "function M.first(a)" }
    for i = 1, 10 do table.insert(body, ("  local n%d = %d"):format(i, i)) end
    vim.list_extend(body, { "  return a", "end", "", "return M" })
    write("a.lua", body)
    baseline.snapshot(repo)
    original = body

    -- The first hunk grows the file, so reverting top-down would put the second back on the wrong line
    edited = vim.deepcopy(body)
    edited[13] = "  local n10 = 1000"
    table.remove(edited, 4)
    table.insert(edited, 4, "  local n1 = 100")
    table.insert(edited, 5, "  local n1b = 101")
    write("a.lua", edited)

    window.open()
  ]])
  child.type_keys("j", "gr")

  h.eq(child.lua_get("original"), child.lua_get("read('a.lua')"))

  child.type_keys("u")
  h.eq(child.lua_get("edited"), child.lua_get("read('a.lua')"))
end

T["Window"]["DOES NOT revert over lines an agent saved after the review was drawn"] = function()
  child.lua([[
    write_two_rows()
    vim.fn.bufload(vim.fn.bufadd(vim.fs.joinpath(repo, "a.lua")))
    window.open()

    agent_saved = { "local function first()", "  return 10", "end", "-- a new line from the agent", "local function second()", "  return 20", "end" }
    write("a.lua", agent_saved)
  ]])
  child.type_keys("j", "gr")

  h.eq(child.lua_get("agent_saved"), child.lua_get("read('a.lua')"))
  h.eq(
    { "`a.lua` changed since the review was drawn, so the review has been refreshed" },
    child.lua_get("notifications")
  )
end

T["Window"]["DOES NOT undo a revert once the reverted lines have changed"] = function()
  child.lua("write_two_rows(); window.open()")
  child.type_keys("j", "gr")
  child.lua([[
    changed = read("a.lua")
    changed[2] = "  return 100"
    write("a.lua", changed)
  ]])
  child.type_keys("u")

  h.eq(child.lua_get("changed"), child.lua_get("read('a.lua')"))
  h.eq({ "`a.lua` has changed since the revert, so it cannot be undone" }, child.lua_get("notifications"))
end

T["Window"]["commenting on a deleted line anchors to the line above and quotes what was removed"] = function()
  child.lua([[
    write("a.lua", { "local a = 1", "local gone = 2", "local c = 3" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 1", "local c = 3" })

    package.loaded["codecompanion.interactions.shared.input"].open = function(opts)
      opts.on_submit("Why remove this?")
    end

    window.open()
    focus_pane_row(2)
  ]])
  child.type_keys("gc")

  h.eq(1, child.lua_get("store.comments(repo)[1].start_line"))
  h.eq("local gone = 2", child.lua_get("store.comments(repo)[1].code"))
end

T["Window"]["opening a round whose only changes are auto-accepted closes it"] = function()
  child.lua([[
    config.interactions.code_review.opts.auto_accept = { "*.lock" }
    write("a.lock", { "v1" })
    baseline.snapshot(repo)
    store.begin_round(repo)
    write("a.lock", { "v2" })

    window.open()
  ]])

  h.is_false(child.lua_get("store.round_open(repo)"))
end

T["Window"]["reports a worktree it cannot read and leaves the round open"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    store.begin_round(repo)

    local diff = baseline.diff
    baseline.diff = function() return nil end
    window.open()
    baseline.diff = diff
  ]])

  h.eq({ "Could not read the worktree" }, child.lua_get("notifications"))
  h.is_true(child.lua_get("store.round_open(repo)"))
end

T["Window"]["Branch from a cleared review still shows every change on the branch"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    git("add", "--all")
    git("commit", "--quiet", "-m", "init")
    git("branch", "-M", "main")
    git("checkout", "--quiet", "-b", "feature")
    write("b.lua", { "local b = 1" })
    git("add", "--all")
    git("commit", "--quiet", "-m", "add b")

    baseline.snapshot(repo)
    write("a.lua", { "local a = 10" })
    window.open()
  ]])
  child.type_keys("ga")
  h.eq({ "No edits left to review" }, child.lua_get("get_rows()"))

  child.lua("review.review_branch()")

  h.eq(
    { "2 files, 2 hunks", "a.lua  +1 -1", "  +1 -1  local a = 10", "b.lua  +1 -0", "  +1 -0  local b = 1" },
    child.lua_get("get_rows()")
  )
end

return T
