local h = require("tests.helpers")

local new_set = MiniTest.new_set

local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- expose helpers and config in the child for convenience
        h = require('tests.helpers')
      ]])
    end,
    post_once = child.stop,
  },
})

T["write_text_file uses buffer when present"] = function()
  local result = child.lua([[
    -- Prepare mocks
    package.loaded["codecompanion.utils.buffers"] = {
      get_bufnr_from_path = function(path) return 42 end,
      write = function(bufnr, content)
        _G._buf_write = { bufnr = bufnr, content = content, path = path }
      end,
    }

    package.loaded["codecompanion.utils.files"] = {
      write_to_path = function(path, content)
        _G._file_write = { path = path, content = content }
      end,
      read = function() return "" end,
    }

    -- Ensure we control uv when module is required (not strictly needed for write)
    vim.uv = vim.uv or {}
    -- Force reload of module under test
    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, err = fs.write_text_file("/some/path.txt", "hello world")
    return { ok = ok, err = err, buf_write = _G._buf_write, file_write = _G._file_write }
  ]])

  h.is_true(result.ok)
  h.eq(nil, result.err)
  h.is_true(result.buf_write ~= nil)
  h.eq(42, result.buf_write.bufnr)
  h.eq("hello world", result.buf_write.content)
  h.eq(nil, result.file_write)
end

T["write_text_file falls back to file write when no buffer"] = function()
  local result = child.lua([[
    -- Mocks: no buffer
    package.loaded["codecompanion.utils.buffers"] = {
      get_bufnr_from_path = function(path) return nil end,
      write = function() error("should not be called") end,
    }

    package.loaded["codecompanion.utils.files"] = {
      write_to_path = function(path, content)
        _G._file_write = { path = path, content = content }
      end,
      read = function() return "" end,
    }

    vim.uv = vim.uv or {}
    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, err = fs.write_text_file("/some/other.txt", "file-body")
    return { ok = ok, err = err, file_write = _G._file_write }
  ]])

  h.is_true(result.ok)
  h.eq(nil, result.err)
  h.is_true(result.file_write ~= nil)
  h.eq("/some/other.txt", result.file_write.path)
  h.eq("file-body", result.file_write.content)
end

T["write_text_file returns error when buffer write fails"] = function()
  local result = child.lua([[
    package.loaded["codecompanion.utils.buffers"] = {
      get_bufnr_from_path = function(path) return 7 end,
      write = function(bufnr, content) error("boom") end,
    }

    package.loaded["codecompanion.utils.files"] = {
      write_to_path = function() end,
      read = function() return "" end,
    }

    vim.uv = vim.uv or {}
    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, err = fs.write_text_file("/err/path", "x")
    return { ok = ok, err = err }
  ]])

  h.eq(nil, result.ok)
  h.is_true(type(result.err) == "string")
  h.is_true(result.err:match("Buffer write failed") ~= nil)
end

T["write_text_file returns error when file write fails"] = function()
  local result = child.lua([[
    package.loaded["codecompanion.utils.buffers"] = {
      get_bufnr_from_path = function(path) return nil end,
      write = function() end,
    }

    package.loaded["codecompanion.utils.files"] = {
      write_to_path = function(path, content) error("disk is full") end,
      read = function() return "" end,
    }

    vim.uv = vim.uv or {}
    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, err = fs.write_text_file("/disk/full", "data")
    return { ok = ok, err = err }
  ]])

  h.eq(nil, result.ok)
  h.is_true(type(result.err) == "string")
  h.is_true(result.err:match("File write failed") ~= nil)
end

T["read_text_file returns ENOENT when file missing"] = function()
  local result = child.lua([[
    -- stub uv.fs_stat to return nil (missing)
    vim.uv = { fs_stat = function(path) return nil end }

    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return "shouldn't be called" end,
    }

    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, data = fs.read_text_file("/no/such/file")
    return { ok = ok, data = data }
  ]])

  h.eq(false, result.ok)
  h.eq("ENOENT", result.data)
end

-- Split read_text_file coverage into multiple focused tests
local content = "first line\nsecond line\nthird"

T["read_text_file returns full content when no opts provided"] = function()
  local result = child.lua(string.format(
    [[
    vim.uv = { fs_stat = function(path) return { size = 123 } end }

    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return %q end,
    }

    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, data = fs.read_text_file("/some/path")
    return { ok = ok, data = data }
  ]],
    content
  ))

  h.is_true(result.ok)
  h.eq(content, result.data)
end

T["read_text_file returns from given line to EOF"] = function()
  local result = child.lua(string.format(
    [[
    vim.uv = { fs_stat = function(path) return { size = 123 } end }

    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return %q end,
    }

    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, data = fs.read_text_file("/some/path", { line = 2 })
    return { ok = ok, data = data }
  ]],
    content
  ))

  h.is_true(result.ok)
  h.eq("second line\nthird", result.data)
end

T["read_text_file normalizes line 0 to 1"] = function()
  local result = child.lua(string.format(
    [[
    vim.uv = { fs_stat = function(path) return { size = 123 } end }

    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return %q end,
    }

    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, data = fs.read_text_file("/some/path", { line = 0 })
    return { ok = ok, data = data }
  ]],
    content
  ))

  h.is_true(result.ok)
  h.eq(content, result.data)
end

T["read_text_file limit larger than lines returns full content"] = function()
  local result = child.lua(string.format(
    [[
    vim.uv = { fs_stat = function(path) return { size = 123 } end }

    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return %q end,
    }

    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, data = fs.read_text_file("/some/path", { limit = 5 })
    return { ok = ok, data = data }
  ]],
    content
  ))

  h.is_true(result.ok)
  h.eq(content, result.data)
end

T["read_text_file limit 2 returns first two lines"] = function()
  local result = child.lua(string.format(
    [[
    vim.uv = { fs_stat = function(path) return { size = 123 } end }

    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return %q end,
    }

    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, data = fs.read_text_file("/some/path", { limit = 2 })
    return { ok = ok, data = data }
  ]],
    content
  ))

  h.is_true(result.ok)
  h.eq("first line\nsecond line", result.data)
end

T["read_text_file line 2 limit 1 returns only second line"] = function()
  local result = child.lua(string.format(
    [[
    vim.uv = { fs_stat = function(path) return { size = 123 } end }

    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return %q end,
    }

    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, data = fs.read_text_file("/some/path", { line = 2, limit = 1 })
    return { ok = ok, data = data }
  ]],
    content
  ))

  h.is_true(result.ok)
  h.eq("second line", result.data)
end

T["read_text_file limit 0 returns empty string"] = function()
  local result = child.lua(string.format(
    [[
    vim.uv = { fs_stat = function(path) return { size = 123 } end }

    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return %q end,
    }

    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, data = fs.read_text_file("/some/path", { limit = 0 })
    return { ok = ok, data = data }
  ]],
    content
  ))

  h.is_true(result.ok)
  h.eq("", result.data)
end

T["read_text_file start line beyond EOF returns empty string"] = function()
  local result = child.lua(string.format(
    [[
    vim.uv = { fs_stat = function(path) return { size = 123 } end }

    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return %q end,
    }

    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, data = fs.read_text_file("/some/path", { line = 4 })
    return { ok = ok, data = data }
  ]],
    content
  ))

  h.is_true(result.ok)
  h.eq("", result.data)
end

T["read_text_file treats vim.NIL opts as no opts"] = function()
  local result = child.lua(string.format(
    [[
    vim.uv = { fs_stat = function(path) return { size = 123 } end }

    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return %q end,
    }

    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    -- Pass vim.NIL as opts to simulate real-world ACP behavior
    local ok, data = fs.read_text_file("/some/path", vim.NIL)
    return { ok = ok, data = data }
  ]],
    content
  ))

  h.is_true(result.ok)
  h.eq(content, result.data)
end

T["read_text_file integration reads real file"] = function()
  local result = child.lua([[
    -- Construct an absolute path to the stub file in the repo
    local path = vim.fn.getcwd() .. "/tests/stubs/fs_read_text_file.txt"

    -- Ensure the stub file exists for the test to be meaningful
    local stat = vim.uv.fs_stat(path)
    if not stat then
      return { ok = false, err = "stub file missing: " .. path }
    end

    -- Reload module under test (no mocks)
    package.loaded["codecompanion.interactions.chat.acp.fs"] = nil
    local fs = require("codecompanion.interactions.chat.acp.fs")

    local ok, data = fs.read_text_file(path)
    return { ok = ok, data = data }
  ]])

  h.is_true(result.ok, result.err)
  h.eq("Hello World\n", result.data)
end

return T
