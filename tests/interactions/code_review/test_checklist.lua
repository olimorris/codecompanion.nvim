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
        checklist = require("codecompanion.interactions.code_review.checklist")
        config = require("codecompanion.config")
        review = require("codecompanion.interactions.code_review")
        store = require("codecompanion.interactions.code_review.store")

        write = function(path, lines)
          vim.fn.mkdir(vim.fs.dirname(vim.fs.joinpath(repo, path)), "p")
          vim.fn.writefile(lines, vim.fs.joinpath(repo, path))
        end

        build = function()
          local built = checklist.build({ root = repo })
          checklist.discard(built.diffs)
          return built.lines
        end

        count_hunks = function()
          local built = checklist.build({ root = repo })
          local hunks = 0
          for _, file_diff in pairs(built.diffs) do
            hunks = hunks + #file_diff.hunks
          end
          checklist.discard(built.diffs)
          return hunks
        end

        entry_field = function(row, key)
          local built = checklist.build({ root = repo })
          local value = built.entries[row][key]
          checklist.discard(built.diffs)
          return value
        end

        -- A round the user commented on and sent, so the next one can be read against it
        send_comment_on_line = function(line, comment)
          store.add_comment(repo, { path = "a.lua", start_line = line, end_line = line, code = "", comment = comment })
          review.consume()
        end

        accept_row = function(row)
          local built = checklist.build({ root = repo })
          for _, id in ipairs(built.entries[row].ids) do
            store.accept(repo, id)
          end
          checklist.discard(built.diffs)
        end

        -- Load the file into a buffer and put an error against it, as an LSP would
        report_error = function(path)
          local bufnr = vim.fn.bufadd(vim.fs.joinpath(repo, path))
          vim.fn.bufload(bufnr)
          vim.bo[bufnr].buflisted = true
          vim.diagnostic.set(vim.api.nvim_create_namespace("test"), bufnr, {
            { lnum = 0, col = 0, message = "boom", severity = vim.diagnostic.severity.ERROR },
          })
        end
      ]])
    end,
    pre_case = function()
      child.lua([[
        storage_dir = vim.fn.tempname()
        config.interactions.code_review.opts.storage_dir = storage_dir
        config.interactions.code_review.opts.auto_accept = {}

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

T["Checklist"] = new_set()

T["Checklist"]["leaves out files matching auto_accept"] = function()
  child.lua([[
    write("a.lua", { "local a = 1" })
    write("deps/lock.lock", { "one" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 2" })
    write("deps/lock.lock", { "two" })

    config.interactions.code_review.opts.auto_accept = { "**/*.lock" }
  ]])

  h.eq({ "1 file, 1 hunk, 1 auto-accepted", "a.lua  +1 -1", "  +1 -1  local a = 2" }, child.lua_get("build()"))
end

T["Checklist"]["puts the file with the most changed lines first"] = function()
  child.lua([[
    write("a.lua", { "local a = 1", "local b = 2" })
    write("z.lua", { "local a = 1", "local b = 2", "local c = 3" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 10", "local b = 2" })
    write("z.lua", { "local a = 10", "local b = 20", "local c = 30" })
  ]])

  local lines = child.lua_get("build()")
  h.eq("z.lua  +3 -3", lines[2])
  h.eq("a.lua  +1 -1", lines[4])
end

T["Checklist"]["puts a file with errors above a bigger change"] = function()
  child.lua([[
    write("a.lua", { "local a = 1", "local b = 2", "local c = 3" })
    write("z.lua", { "local a = 1" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 10", "local b = 20", "local c = 30" })
    write("z.lua", { "local a = 10" })

    report_error("z.lua")
  ]])

  local lines = child.lua_get("build()")
  h.eq("2 files, 2 hunks, 1 with errors", lines[1])
  h.eq("z.lua  +1 -1  E1", lines[2])
  h.eq("a.lua  +3 -3", lines[4])
end

T["Checklist"]["keeps a file's position after one of its hunks is accepted"] = function()
  child.lua([[
    write("a.lua", { "local a = 1", "local b = 2", "local c = 3" })
    write("z.lua", { "local a = 1", "local b = 2", "local c = 3", "local d = 4", "local e = 5" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 10", "local b = 20", "local c = 30" })
    write("z.lua", { "local a = 10", "local b = 20", "local c = 3", "local d = 40", "local e = 50" })
  ]])

  h.eq("z.lua  +4 -4", child.lua_get("build()[2]"))

  child.lua([[
    for _, hunk in ipairs(baseline.diff(repo)) do
      if hunk.path == "z.lua" and hunk.line == 1 then
        store.accept(repo, hunk.id)
      end
    end
  ]])

  -- Fewer lines left than a.lua, but the round's size is what orders the list
  h.eq("z.lua  +2 -2", child.lua_get("build()[2]"))
end

T["Checklist"]["groups hunks inside the same function into one row"] = function()
  child.lua([[
    local body = { "local M = {}", "", "function M.first(a)" }
    for i = 1, 10 do table.insert(body, ("  local n%d = %d"):format(i, i)) end
    vim.list_extend(body, { "  return a", "end", "", "return M" })
    write("a.lua", body)
    baseline.snapshot(repo)

    body[4] = "  local n1 = 100"
    body[13] = "  local n10 = 1000"
    write("a.lua", body)
  ]])

  local lines = child.lua_get("build()")
  h.eq({ "1 file, 2 hunks in 1 row", "a.lua  +2 -2", "  +2 -2  in M.first" }, lines)
end

T["Checklist"]["labels a function added in the round as new"] = function()
  child.lua([[
    write("a.lua", { "local M = {}", "", "function M.first()", "  return 1", "end", "", "return M" })
    baseline.snapshot(repo)
    write("a.lua", {
      "local M = {}", "", "function M.first()", "  return 1", "end", "",
      "function M.second()", "  return 2", "end", "", "return M",
    })
  ]])

  h.eq({ "1 file, 1 hunk", "a.lua  +4 -0", "  +4 -0  new M.second" }, child.lua_get("build()"))
end

T["Checklist"]["names a row for the function around a call, not the call"] = function()
  child.lua([[
    write("a.lua", { "local M = {}", "", "function M.complete()", "  return vim", "    .iter({ 'A' })", "    :totable()", "end" })
    baseline.snapshot(repo)
    write("a.lua", { "local M = {}", "", "function M.complete()", "  return vim", "    .iter({ 'A', 'B' })", "    :totable()", "end" })
  ]])

  h.eq({ "1 file, 1 hunk", "a.lua  +1 -1", "  +1 -1  in M.complete" }, child.lua_get("build()"))
end

T["Checklist"]["accepting a row settles an addition git folds into the change beside it"] = function()
  child.lua([[
    local body = { "local M = {}", "", "function M.first(a)" }
    for i = 1, 10 do table.insert(body, ("  local n%d = %d"):format(i, i)) end
    vim.list_extend(body, { "  return a", "end", "", "return M" })
    write("a.lua", body)
    baseline.snapshot(repo)

    body[4] = "  local n1 = 100"
    table.insert(body, 5, "  local extra = true")
    write("a.lua", body)
  ]])

  -- `linematch` shows the change and the insertion as two hunks; git's `--unified=0` reports one
  h.eq({ "1 file, 2 hunks in 1 row", "a.lua  +2 -1", "  +2 -1  in M.first" }, child.lua_get("build()"))

  child.lua("accept_row(3)")
  h.eq({}, child.lua_get("build()"))
end

T["Checklist"]["accepting a row settles a deletion linematch splits off the change beside it"] = function()
  child.lua([[
    write("a.lua", { "local a = 1", "local one = 1", "local two = 2", "local b = 2" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 1", "local two = 20", "local b = 2" })
  ]])

  -- `linematch` shows a deletion then a change; git reports one hunk that starts below the deletion
  h.eq({ "1 file, 2 hunks in 1 row", "a.lua  +1 -2", "  +1 -2  local one = 1" }, child.lua_get("build()"))

  child.lua("accept_row(3)")
  h.eq({}, child.lua_get("build()"))
end

T["Checklist"]["DOES NOT group hunks in different functions"] = function()
  child.lua([[
    write("a.lua", { "local function first()", "  return 1", "end", "local function second()", "  return 2", "end" })
    baseline.snapshot(repo)
    write("a.lua", { "local function first()", "  return 10", "end", "local function second()", "  return 20", "end" })
  ]])

  local lines = child.lua_get("build()")
  h.eq({ "1 file, 2 hunks", "a.lua  +2 -2", "  +1 -1  in first", "  +1 -1  in second" }, lines)
end

T["Checklist"]["groups hunks a git diff context apart when there is no parser"] = function()
  child.lua([[
    write("notes.txt", { "one", "two", "three", "four", "five", "six", "seven", "eight" })
    baseline.snapshot(repo)
    write("notes.txt", { "ONE", "two", "three", "four", "five", "six", "seven", "EIGHT" })
  ]])

  h.eq({ "1 file, 2 hunks in 1 row", "notes.txt  +2 -2", "  +2 -2  ONE" }, child.lua_get("build()"))
end

T["Checklist"]["DOES NOT group hunks further apart than a git diff context"] = function()
  child.lua([[
    write("notes.txt", { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" })
    baseline.snapshot(repo)
    write("notes.txt", { "ONE", "two", "three", "four", "five", "six", "seven", "eight", "NINE" })
  ]])

  h.eq({ "1 file, 2 hunks", "notes.txt  +2 -2", "  +1 -1  ONE", "  +1 -1  NINE" }, child.lua_get("build()"))
end

T["Checklist"]["shows far fewer rows than hunks across a round"] = function()
  child.lua([[
    local body = { "local M = {}", "", "function M.first(a)" }
    for i = 1, 20 do table.insert(body, ("  local n%d = %d"):format(i, i)) end
    vim.list_extend(body, { "  return a", "end", "", "function M.second()", "  return 2", "end", "", "return M" })
    write("a.lua", body)
    write("notes.txt", { "one", "two", "three", "four", "five", "six", "seven", "eight" })
    write("deps/lock.lock", { "one" })
    baseline.snapshot(repo)

    body[4] = "  local n1 = 100"
    body[13] = "  local n10 = 1000"
    body[23] = "  local n20 = 2000"
    body[28] = "  return 20"
    write("a.lua", body)
    write("notes.txt", { "ONE", "two", "three", "FOUR", "five", "six", "SEVEN", "eight" })
    write("deps/lock.lock", { "two" })

    config.interactions.code_review.opts.auto_accept = { "**/*.lock" }
  ]])

  h.eq(7, child.lua_get("count_hunks()"))
  h.eq({
    "2 files, 7 hunks in 3 rows, 1 auto-accepted",
    "a.lua  +4 -4",
    "  +3 -3  in M.first",
    "  +1 -1  in M.second",
    "notes.txt  +3 -3",
    "  +3 -3  ONE",
  }, child.lua_get("build()"))
end

T["Checklist"]["marks a row with the comment sent against its lines last round"] = function()
  child.lua([[
    write("a.lua", { "local a = 1", "local b = 2", "local c = 3" })
    baseline.snapshot(repo)
    write("a.lua", { "local a = 10", "local b = 2", "local c = 3" })
    send_comment_on_line(1, "Use a constant")
    write("a.lua", { "local A = 10", "local b = 2", "local c = 3" })
  ]])

  h.eq({ "1 file, 1 hunk", "a.lua  +1 -1", "  +1 -1  local A = 10 ↳" }, child.lua_get("build()"))
  h.eq({ "Use a constant" }, child.lua_get("entry_field(3, 'sent')"))
end

T["Checklist"]["DOES NOT mark a row far from any sent comment"] = function()
  child.lua([[
    local body = {}
    for i = 1, 20 do body[i] = ("local n%d = %d"):format(i, i) end
    write("a.lua", body)
    baseline.snapshot(repo)
    body[1] = "local n1 = 100"
    write("a.lua", body)
    send_comment_on_line(1, "Use a constant")
    body[20] = "local n20 = 2000"
    write("a.lua", body)
  ]])

  h.eq({ "1 file, 1 hunk", "a.lua  +1 -1", "  +1 -1  local n20 = 2000" }, child.lua_get("build()"))
end

return T
