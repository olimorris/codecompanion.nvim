local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
local new_set = MiniTest.new_set

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        h.setup_plugin()

        config = require("codecompanion.config")
        Watchers = require("codecompanion.interactions.chat.watchers")

        ---A minimal chat double: watchers only touch context_items, add_message and the context UI
        _G.new_chat = function(context_items)
          return {
            context = { render = function() end },
            context_items = context_items,
            messages = {},
            add_message = function(self, data, opts)
              table.insert(self.messages, vim.tbl_deep_extend("force", data, opts or {}))
            end,
          }
        end

        _G.new_buffer = function(lines)
          local bufnr = vim.api.nvim_create_buf(true, true)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
          return bufnr
        end

        ---Write a file, bumping its modification time so a change is always detected
        _G.mtimes = {}
        _G.write_file = function(path, lines)
          vim.fn.writefile(lines, path)
          _G.mtimes[path] = (_G.mtimes[path] or os.time()) + 2
          vim.uv.fs_utime(path, _G.mtimes[path], _G.mtimes[path])
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Watchers"] = new_set()

T["Watchers"]["shares a diff when a watched buffer changes"] = function()
  local result = child.lua([[
    local watchers = Watchers.new()
    local bufnr = _G.new_buffer({ "line 1", "line 2", "line 3" })
    local id = "<buf>test.lua</buf>"
    local chat = _G.new_chat({ { id = id, bufnr = bufnr, opts = { sync_diff = true } } })

    local synced = watchers:sync_buffer({ id = id, bufnr = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "modified line 2" })
    watchers:check_for_changes(chat)

    -- No further changes means no further messages
    local shared = #chat.messages
    watchers:check_for_changes(chat)

    return { synced = synced, shared = shared, messages = chat.messages }
  ]])

  h.is_true(result.synced)
  h.eq(result.shared, 1)
  h.eq(#result.messages, 1)

  local message = result.messages[1]
  h.expect_truthy(message.content:find("````diff", 1, true))
  h.expect_truthy(message.content:find("-line 2", 1, true))
  h.expect_truthy(message.content:find("+modified line 2", 1, true))
  h.eq(message.context.id, "<buf>test.lua</buf>")
end

T["Watchers"]["stops sharing once a watcher is removed"] = function()
  local messages = child.lua([[
    local watchers = Watchers.new()
    local bufnr = _G.new_buffer({ "line 1" })
    local id = "<buf>test.lua</buf>"
    local chat = _G.new_chat({ { id = id, bufnr = bufnr, opts = { sync_diff = true } } })

    watchers:sync_buffer({ id = id, bufnr = bufnr })
    watchers:unsync(id)

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified line 1" })
    watchers:check_for_changes(chat)

    return chat.messages
  ]])

  h.eq(#messages, 0)
end

T["Watchers"]["ignores context items that are not watched"] = function()
  local messages = child.lua([[
    local watchers = Watchers.new()
    local bufnr = _G.new_buffer({ "line 1" })
    local chat = _G.new_chat({ { id = "<buf>test.lua</buf>", bufnr = bufnr, opts = { sync_diff = true } } })

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified line 1" })
    watchers:check_for_changes(chat)

    return chat.messages
  ]])

  h.eq(#messages, 0)
end

T["Watchers"]["does not watch an invalid buffer"] = function()
  h.is_false(child.lua_get([[Watchers.new():sync_buffer({ id = "<buf>nope</buf>", bufnr = -1 })]]))
end

T["Watchers"]["shares a diff when a watched file changes"] = function()
  local result = child.lua([[
    local path = vim.fn.tempname() .. ".lua"
    _G.write_file(path, { "local x = 1" })

    local id = "<file>" .. path .. "</file>"
    local watchers = Watchers.new()
    local chat = _G.new_chat({ { id = id, path = path, opts = { sync_diff = true } } })

    local synced = watchers:sync_file({ id = id, path = path })
    _G.write_file(path, { "local x = 1", "local y = 2" })
    watchers:check_for_changes(chat)

    return { id = id, synced = synced, messages = chat.messages }
  ]])

  h.is_true(result.synced)
  h.eq(#result.messages, 1)

  local message = result.messages[1]
  h.expect_truthy(message.content:find("````diff", 1, true))
  h.expect_truthy(message.content:find("+local y = 2", 1, true))
  h.eq(message.context.id, result.id)

  -- The attachment envelope is not part of the diff
  h.eq(select(2, message.content:gsub("</attachment>", "")), 1)
end

T["Watchers"]["reports when a watched file is removed"] = function()
  local result = child.lua([[
    local path = vim.fn.tempname() .. ".lua"
    _G.write_file(path, { "local x = 1" })

    local id = "<file>" .. path .. "</file>"
    local watchers = Watchers.new()
    local chat = _G.new_chat({ { id = id, path = path, opts = { sync_diff = true } } })
    watchers:sync_file({ id = id, path = path })

    os.remove(path)
    watchers:check_for_changes(chat)

    return { messages = chat.messages, still_watched = watchers.watchers[id] ~= nil }
  ]])

  h.eq(#result.messages, 1)
  h.expect_truthy(result.messages[1].content:find("has been removed", 1, true))
  h.is_false(result.still_watched)
end

T["Watchers"]["does not watch a file that cannot be read"] = function()
  h.is_false(
    child.lua_get([[Watchers.new():sync_file({ id = "<file>nope.lua</file>", path = "/nonexistent/nope.lua" })]])
  )
end

T["Watchers"]["reports when a watched buffer is deleted"] = function()
  local result = child.lua([[
    local watchers = Watchers.new()
    local bufnr = _G.new_buffer({ "line 1" })
    local id = "<buf>test.lua</buf>"
    local item = { id = id, bufnr = bufnr, opts = { sync_diff = true } }
    local chat = _G.new_chat({ item })
    watchers:sync_buffer({ id = id, bufnr = bufnr })

    vim.api.nvim_buf_delete(bufnr, { force = true })
    watchers:check_for_changes(chat)

    return {
      messages = chat.messages,
      still_watched = watchers.watchers[id] ~= nil,
      still_synced = item.opts.sync_diff,
    }
  ]])

  h.eq(#result.messages, 1)
  h.expect_truthy(result.messages[1].content:find("has been deleted", 1, true))
  h.is_false(result.still_watched)
  -- The context item stops advertising itself as synced
  h.is_false(result.still_synced)
end

T["Watchers"]["diffs formatter-formatted content rather than the raw content"] = function()
  local messages = child.lua([[
    config.context.formatters.ccsync = function(raw)
      return raw:upper()
    end

    local path = vim.fn.tempname() .. ".ccsync"
    _G.write_file(path, { "before" })

    local id = "<file>" .. path .. "</file>"
    local watchers = Watchers.new()
    local chat = _G.new_chat({ { id = id, path = path, opts = { sync_diff = true } } })
    watchers:sync_file({ id = id, path = path })

    _G.write_file(path, { "before", "after" })
    watchers:check_for_changes(chat)

    return chat.messages
  ]])

  h.eq(#messages, 1)
  h.expect_truthy(messages[1].content:find("+AFTER", 1, true))
end

return T
