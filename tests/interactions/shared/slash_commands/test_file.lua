local new_set = MiniTest.new_set
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[h = require("tests.helpers")]])
    end,
    post_once = child.stop,
  },
})

---Build a working directory and a second directory, then run the picker over both
---@param dirs string Lua source for the `opts.dirs` table
---@return string[]
local function pick_files(dirs)
  return child.lua(string.format(
    [[
    local cwd = vim.fn.tempname()
    local extra = vim.fn.tempname()
    vim.fn.mkdir(cwd, "p")
    vim.fn.mkdir(extra, "p")
    vim.fn.writefile({ "in cwd" }, cwd .. "/in_cwd.txt")
    vim.fn.writefile({ "in extra" }, extra .. "/in_extra.txt")
    vim.fn.chdir(cwd)

    local picked
    vim.ui.select = function(items, _, on_choice)
      picked = vim.tbl_map(function(item)
        return vim.fn.fnamemodify(item.path, ":t")
      end, items)
      on_choice(nil)
    end

    local slash = require("codecompanion.interactions.shared.slash_commands.file")
    slash.cli_render({ opts = { provider = "default", dirs = %s } }, function() end)

    table.sort(picked)
    return picked
  ]],
    dirs
  ))
end

T["File"] = new_set()

T["File"]["searches the current working directory when no dirs are configured"] = function()
  h.eq({ "in_cwd.txt" }, pick_files("{}"))
end

T["File"]["searches a configured directory alongside the current working directory"] = function()
  h.eq({ "in_cwd.txt", "in_extra.txt" }, pick_files("{ extra }"))
end

T["File"]["skips a configured directory that does not exist"] = function()
  h.eq({ "in_cwd.txt" }, pick_files([[{ "/does/not/exist" }]]))
end

T["File"]["adds an image as an image message"] = function()
  child.lua([[
    _G.chat = h.setup_chat_buffer()
    _G.chat.adapter.opts = vim.tbl_extend("force", _G.chat.adapter.opts or {}, { vision = true })

    local slash = require("codecompanion.interactions.shared.slash_commands.file")
      .new({ Chat = _G.chat, config = { opts = { contains_code = true } } })
    slash:output({ path = vim.fn.getcwd() .. "/tests/stubs/logo.png" })
  ]])

  local message = child.lua([[return _G.chat.messages[#_G.chat.messages] ]])
  h.eq("image", message._meta.tag)
  h.eq("image/png", message.context.mimetype)

  local context = child.lua([[return _G.chat.context_items[#_G.chat.context_items].id]])
  h.eq("<image>tests/stubs/logo.png</image>", context)
end

T["File"]["DOES NOT add an image when the adapter has no vision support"] = function()
  local count = child.lua([[
    _G.chat = h.setup_chat_buffer()
    _G.chat.adapter.opts = vim.tbl_extend("force", _G.chat.adapter.opts or {}, { vision = false })
    local before = #_G.chat.messages

    local slash = require("codecompanion.interactions.shared.slash_commands.file")
      .new({ Chat = _G.chat, config = { opts = { contains_code = true } } })
    slash:output({ path = vim.fn.getcwd() .. "/tests/stubs/logo.png" })

    return #_G.chat.messages - before
  ]])
  h.eq(0, count)
end

return T
