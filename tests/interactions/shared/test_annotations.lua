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

        _G.annotations = require("codecompanion.interactions.shared.annotations")

        -- Stub the input popup so `create` submits a comment immediately
        _G.stub_input = function(comment)
          package.loaded["codecompanion.interactions.shared.input"].open = function(opts)
            opts.on_submit(comment)
          end
        end
      ]])
    end,
    post_case = function()
      child.lua([[annotations.clear()]])
    end,
    post_once = child.stop,
  },
})

T["Annotations"] = new_set()

T["Annotations"]["add appends to the store"] = function()
  child.lua([[
    annotations.add({
      comment = "Handle the nil case",
      code = "local x = 1",
      filetype = "lua",
      relative_path = "lua/foo.lua",
      start_line = 1,
      end_line = 1,
    })
  ]])

  h.eq(1, child.lua_get("annotations.count()"))
  h.eq("Handle the nil case", child.lua_get("annotations.all()[1].comment"))
end

T["Annotations"]["CLEAR empties the store"] = function()
  child.lua([[
    annotations.add({ comment = "one", code = "", filetype = "lua", relative_path = "foo.lua", start_line = 1, end_line = 1 })
    annotations.add({ comment = "two", code = "", filetype = "lua", relative_path = "foo.lua", start_line = 2, end_line = 2 })
    annotations.clear()
  ]])

  h.eq(0, child.lua_get("annotations.count()"))
end

T["Annotations"]["CREATE snapshots the current line when there is no visual selection"] = function()
  child.lua([[
    stub_input("This should handle the nil case")

    vim.cmd("edit! test_annotations_fixture.lua")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1", "local b = 2", "local c = 3" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    annotations.create({ range = 0 })
  ]])

  local pending = child.lua_get("annotations.all()")
  h.eq(1, #pending)
  h.eq("This should handle the nil case", pending[1].comment)
  h.eq("local b = 2", pending[1].code)
  h.eq(2, pending[1].start_line)
  h.eq(2, pending[1].end_line)

  child.lua([[vim.cmd("bwipeout! test_annotations_fixture.lua")]])
end

T["Annotations"]["CREATE snapshots a visual selection"] = function()
  child.lua([[
    stub_input("Rename these")

    vim.cmd("edit! test_annotations_fixture.lua")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local a = 1", "local b = 2", "local c = 3" })
    vim.api.nvim_buf_set_mark(buf, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(buf, ">", 2, 10, {})

    annotations.create({ range = 2 })
  ]])

  local pending = child.lua_get("annotations.all()")
  h.eq(1, #pending)
  h.eq("Rename these", pending[1].comment)
  h.eq("local a = 1\nlocal b = 2", pending[1].code)
  h.eq(1, pending[1].start_line)
  h.eq(2, pending[1].end_line)

  child.lua([[vim.cmd("bwipeout! test_annotations_fixture.lua")]])
end

T["Annotations"]["CREATE does nothing when sending code is disabled"] = function()
  child.lua([[
    stub_input("Should not be added")
    config = require('codecompanion.config')
    config.opts.send_code = false

    annotations.create({ range = 0 })

    config.opts.send_code = true
  ]])

  h.eq(0, child.lua_get("annotations.count()"))
end

return T
