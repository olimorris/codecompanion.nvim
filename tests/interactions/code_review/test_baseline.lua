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
  -- The added line is what the change became, so it wins over the line it replaced
  h.eq("+1 -1 local b = 20", hunks[1].summary)
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
  h.eq("+2 -0 local b = 1", hunks[1].summary)
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
  -- Nothing was added, so the removed line is all there is to show
  h.eq("+0 -2 local b = 1", hunks[1].summary)
end

T["Baseline"]["a removed line that reads like a diff header stays inside its hunk"] = function()
  child.lua([[
    write("a.lua", { "-- one", "local a = 1", "local b = 2", "-- two", "local c = 3" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 1", "local b = 2", "local c = 3" })

    hunks = baseline.diff(repo)
  ]])

  -- Git renders a removed `-- one` as `--- one`, which is the shape of a file header
  h.eq(2, child.lua_get("#hunks"))
  h.eq("+0 -1 -- one", child.lua_get("hunks[1].summary"))
  h.eq("+0 -1 -- two", child.lua_get("hunks[2].summary"))
  -- Swallowing them would leave both hunks with an empty body, and so the same id
  h.is_true(child.lua_get("hunks[1].id ~= hunks[2].id"))
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

T["Baseline"]["a nested repo with no commits doesn't block the review"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    vim.system({ "git", "init", "--quiet", vim.fs.joinpath(repo, "nested") }):wait()
    vim.fn.writefile({ "local n = 1" }, vim.fs.joinpath(repo, "nested", "n.lua"))
    baseline.snapshot(repo)
    write("a.lua", { "local a = 2" })
  ]])

  h.expect_match(child.lua_get("baseline.get(repo)"), "^%x+$")

  -- The nested repo can't be indexed, so it's left out of the review entirely
  local hunks = child.lua_get("baseline.diff(repo)")
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

-- NOTE: Use this to prove to a user that we never touch their git index!
T["Baseline"]["a review never touches the user's index"] = function()
  child.lua([[
    commit("init")
    write("a.lua", { "local a = 1" })
    write("b.lua", { "local b = 2" })
    vim.system({ "git", "-C", repo, "add", "b.lua" }):wait()

    local user_index = vim.fs.joinpath(repo, ".git", "index")
    local read = function()
      return table.concat(vim.fn.readfile(user_index, "b"), "\n")
    end

    local before = read()
    baseline.snapshot(repo)
    write("a.lua", { "local a = 100" })
    baseline.diff(repo)
    baseline.snapshot(repo)

    untouched = read() == before
    staged = vim.trim(vim.system({ "git", "-C", repo, "diff", "--cached", "--name-only" }, { text = true }):wait().stdout)
  ]])

  h.is_true(child.lua_get("untouched"))
  h.eq("b.lua", child.lua_get("staged"))
end

T["Baseline"]["a lock left by a dead Neovim is cleared and the review carries on"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 100" })

    index = vim.fs.joinpath(
      vim.trim(vim.system({ "git", "-C", repo, "rev-parse", "--absolute-git-dir" }, { text = true }):wait().stdout),
      "codecompanion-index"
    )
    vim.fn.writefile({}, index .. ".lock")
    -- Far older than any snapshot takes, so it can only have been abandoned
    local long_ago = os.time() - 600
    vim.uv.fs_utime(index .. ".lock", long_ago, long_ago)

    hunks = baseline.diff(repo)
  ]])

  h.eq(1, child.lua_get("#hunks"))
  h.eq("a.lua", child.lua_get("hunks[1].path"))
  h.eq(vim.NIL, child.lua_get("vim.uv.fs_stat(index .. '.lock')"))
end

T["Baseline"]["a lock another Neovim still holds is left alone"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 100" })

    index = vim.fs.joinpath(
      vim.trim(vim.system({ "git", "-C", repo, "rev-parse", "--absolute-git-dir" }, { text = true }):wait().stdout),
      "codecompanion-index"
    )
    vim.fn.writefile({}, index .. ".lock")

    hunks = baseline.diff(repo)
  ]])

  -- Nil rather than an empty list, so a caller can tell this apart from there being no changes
  h.eq(vim.NIL, child.lua_get("hunks"))
  h.is_true(child.lua_get("vim.uv.fs_stat(index .. '.lock') ~= nil"))
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
