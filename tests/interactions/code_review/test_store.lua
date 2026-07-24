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

T["Store"] = new_set()

T["Store"]["adds and fetches a comment to and from the markdown file"] = function()
  child.lua([[
    store.add_comment(repo, {
      comment = "This should handle the nil case",
      code = "local x = call()\nreturn x.value",
      filetype = "lua",
      path = "lua/foo.lua",
      start_line = 40,
      end_line = 45,
    })
  ]])

  local comments = child.lua_get("store.comments(repo)")
  h.eq(1, #comments)
  h.eq("This should handle the nil case", comments[1].comment)
  h.eq("local x = call()\nreturn x.value", comments[1].code)
  h.eq("lua", comments[1].filetype)
  h.eq("lua/foo.lua", comments[1].path)
  h.eq(40, comments[1].start_line)
  h.eq(45, comments[1].end_line)
end

T["Store"]["keeps comments in the order they were added"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "first", code = "local a", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })
    store.add_comment(repo, { comment = "second", code = "local b", filetype = "lua", path = "b.lua", start_line = 2, end_line = 2 })
  ]])

  local comments = child.lua_get("store.comments(repo)")
  h.eq(2, #comments)
  h.eq("first", comments[1].comment)
  h.eq("second", comments[2].comment)
end

T["Store"]["deleting a section removes the comment"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "keep", code = "local a", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })
    store.add_comment(repo, { comment = "retract", code = "local b", filetype = "lua", path = "b.lua", start_line = 2, end_line = 2 })

    local files = require("codecompanion.utils.files")
    local markdown = files.read(store.comments_path(repo))
    files.write_to_path(store.comments_path(repo), (markdown:gsub("## b%.lua.*", "")))
  ]])

  local comments = child.lua_get("store.comments(repo)")
  h.eq(1, #comments)
  h.eq("keep", comments[1].comment)
end

T["Store"]["skips a section with no comment text"] = function()
  child.lua([[
    require("codecompanion.utils.files").write_to_path(
      store.comments_path(repo),
      table.concat({
        "## a.lua:1-1",
        "",
        "````lua",
        "local a = 1",
        "````",
        "",
        "## b.lua:2-2",
        "",
        "````lua",
        "local b = 2",
        "````",
        "",
        "A real comment",
      }, "\n")
    )
  ]])

  local comments = child.lua_get("store.comments(repo)")
  h.eq(1, #comments)
  h.eq("b.lua", comments[1].path)
  h.eq("A real comment", comments[1].comment)
end

T["Store"]["clear_comments empties the store"] = function()
  child.lua([[
    store.add_comment(repo, { comment = "gone", code = "local a", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 })
    store.clear_comments(repo)
  ]])

  h.eq(0, child.lua_get("#store.comments(repo)"))
end

T["Store"]["tracks edited files once, relative to the root"] = function()
  child.lua([[
    store.track(repo, vim.fs.joinpath(repo, "lua/foo.lua"))
    store.track(repo, vim.fs.joinpath(repo, "lua/foo.lua"))
    store.track(repo, vim.fs.joinpath(repo, "lua/bar.lua"))
    store.track(repo, "/somewhere/else/baz.lua")
  ]])

  h.eq({ "lua/foo.lua", "lua/bar.lua" }, child.lua_get("store.edited(repo)"))
end

T["Store"]["clear_edited forgets the edited files"] = function()
  child.lua([[
    store.track(repo, vim.fs.joinpath(repo, "lua/foo.lua"))
    store.clear_edited(repo)
  ]])

  h.eq(0, child.lua_get("#store.edited(repo)"))
end

T["Store"]["comments are scoped per branch"] = function()
  child.lua([[
    commit("init")
    first = baseline.get_branch(repo)
    local context = { comment = "on the first branch", code = "local a", filetype = "lua", path = "a.lua", start_line = 1, end_line = 1 }
    store.add_comment(repo, context)
    checkout("-b", "other")
  ]])

  h.eq(0, child.lua_get("#store.comments(repo)"))

  child.lua([[checkout(first)]])
  h.eq(1, child.lua_get("#store.comments(repo)"))
end

T["Store"]["the review file path is the same on every branch"] = function()
  child.lua([[
    commit("init")
    first_path = store.review_path(repo)
    checkout("-b", "other")
  ]])

  h.eq(child.lua_get("first_path"), child.lua_get("store.review_path(repo)"))
end

T["Store"]["a detached HEAD falls back to repo-level storage"] = function()
  child.lua([[
    commit("init")
    branch_path = store.comments_path(repo)
    checkout("--detach")
  ]])

  -- No branch to scope by, so comments sit next to the repo-level review file
  h.eq(
    child.lua_get("vim.fs.dirname(store.review_path(repo))"),
    child.lua_get("vim.fs.dirname(store.comments_path(repo))")
  )
  h.is_true(child.lua_get("branch_path ~= store.comments_path(repo)"))
end

return T
