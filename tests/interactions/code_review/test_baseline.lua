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

T["Baseline"] = new_set()

T["Baseline"]["snapshot creates the ref"] = function()
  h.eq(vim.NIL, child.lua_get("baseline.get(repo)"))

  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
  ]])

  h.expect_match(child.lua_get("baseline.get(repo)"), "^%x+$")
end

T["Baseline"]["diff reports one hunk per change with line numbers"] = function()
  child.lua([[
    write("a.lua", { "local a = 1", "local b = 2", "local c = 3" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 1", "local b = 20", "local c = 3" })
  ]])

  local hunks = child.lua_get("baseline.diff(repo)")
  h.eq(1, #hunks)
  h.eq("a.lua", hunks[1].path)
  h.eq(2, hunks[1].line)
  h.expect_starts_with("%+1 %-1", hunks[1].summary)
end

T["Baseline"]["diff includes files created after the baseline"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    write("b.lua", { "local b = 1", "local c = 2" })
  ]])

  local hunks = child.lua_get("baseline.diff(repo)")
  h.eq(1, #hunks)
  h.eq("b.lua", hunks[1].path)
  h.eq(1, hunks[1].line)
  h.eq("+2 -0", hunks[1].summary)
end

T["Baseline"]["diff reports deleted files"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    write("b.lua", { "local b = 1", "local c = 2" })
    baseline.snapshot(repo)
    vim.fn.delete(vim.fs.joinpath(repo, "b.lua"))
  ]])

  local hunks = child.lua_get("baseline.diff(repo)")
  h.eq(1, #hunks)
  h.eq("b.lua", hunks[1].path)
  h.eq(1, hunks[1].line)
  h.eq("+0 -2", hunks[1].summary)
end

T["Baseline"]["diff scopes to the given paths"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    write("b.lua", { "local b = 2" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 10" })
    write("b.lua", { "local b = 20" })
  ]])

  local hunks = child.lua_get([[baseline.diff(repo, { "a.lua" })]])
  h.eq(1, #hunks)
  h.eq("a.lua", hunks[1].path)
end

T["Baseline"]["baselines are scoped per branch"] = function()
  child.lua([[
    commit("init")
    first = baseline.get_branch(repo)
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    checkout("-b", "other")
  ]])

  h.eq(vim.NIL, child.lua_get("baseline.get(repo)"))

  child.lua([[checkout(first)]])
  h.expect_match(child.lua_get("baseline.get(repo)"), "^%x+$")
end

T["Baseline"]["each worktree keeps its own baseline"] = function()
  child.lua([[
    commit("init")
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)

    worktree = vim.fn.tempname()
    vim.system({ "git", "-C", repo, "worktree", "add", "--quiet", "-b", "agent", worktree }):wait()
    worktree = vim.uv.fs_realpath(worktree)
  ]])

  -- The main checkout's baseline is invisible in the worktree, even via the alias ref
  h.eq(vim.NIL, child.lua_get("baseline.get(worktree)"))
  h.eq(
    "",
    child.lua_get(
      [[vim.trim(vim.system({ "git", "-C", worktree, "rev-parse", "--quiet", "--verify", "refs/worktree/codecompanion/baseline" }, { text = true }):wait().stdout or "")]]
    )
  )
  h.expect_match(child.lua_get("baseline.get(repo)"), "^%x+$")
end

T["Baseline"]["the alias ref points at the branch baseline"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    sha = baseline.snapshot(repo)
  ]])

  h.eq(
    child.lua_get("sha"),
    child.lua_get(
      [[vim.trim(vim.system({ "git", "-C", repo, "rev-parse", "refs/worktree/codecompanion/baseline" }, { text = true }):wait().stdout)]]
    )
  )
end

return T
