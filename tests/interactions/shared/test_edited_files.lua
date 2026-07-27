local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
local new_set = MiniTest.new_set

T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        h.setup_plugin()

        _G.edited_files = require("codecompanion.interactions.shared.edited_files")
        _G.fire = function(data)
          vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionFileEdited", data = data })
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Edited files"] = new_set()

T["Edited files"]["starts empty"] = function()
  h.eq(0, child.lua_get("#edited_files.all()"))
end

T["Edited files"]["records an edited file from the FileEdited event"] = function()
  child.lua([[fire({ path = "/project/lua/foo.lua", tool = "insert_edit_into_file", line = 40 })]])

  local edits = child.lua_get("edited_files.all()")
  h.eq(1, #edits)
  h.eq("/project/lua/foo.lua", edits[1].path)
  h.eq("insert_edit_into_file", edits[1].tool)
  h.eq(40, edits[1].line)
end

T["Edited files"]["ignores edits without a path"] = function()
  child.lua([[fire({ tool = "insert_edit_into_file" })]])

  h.eq(0, child.lua_get("#edited_files.all()"))
end

T["Edited files"]["refreshes the entry when a file is edited again"] = function()
  child.lua([[
    fire({ path = "/project/lua/foo.lua", tool = "insert_edit_into_file", line = 40 })
    fire({ path = "/project/lua/bar.lua", tool = "create_file" })
    fire({ path = "/project/lua/foo.lua", tool = "insert_edit_into_file", line = 88 })
  ]])

  local edits = child.lua_get("edited_files.all()")
  h.eq(2, #edits)
  h.eq("/project/lua/foo.lua", edits[1].path)
  h.eq(88, edits[1].line)
  h.eq("/project/lua/bar.lua", edits[2].path)
end

T["Edited files"]["to_quickfix notifies when no files have been edited"] = function()
  child.lua([[
    package.loaded["codecompanion.utils"].notify = function(msg, level)
      _G.notified = msg
    end

    edited_files.to_quickfix()
  ]])

  h.eq("No files have been edited this session", child.lua_get("_G.notified"))
  h.eq(0, child.lua_get("#vim.fn.getqflist()"))
end

T["Edited files"]["to_quickfix lists the edited files"] = function()
  child.lua([[
    fire({ path = "/project/lua/foo.lua", tool = "insert_edit_into_file", line = 40 })
    fire({ path = "/project/lua/bar.lua", tool = "create_file" })

    edited_files.to_quickfix()
  ]])

  local qf = child.lua_get("vim.fn.getqflist({ title = true, items = true })")
  h.eq("Files edited by the LLM", qf.title)
  h.eq(2, #qf.items)
  h.eq(40, qf.items[1].lnum)
  h.eq("edited by insert_edit_into_file", qf.items[1].text)
  h.eq("created by create_file", qf.items[2].text)
end

return T
