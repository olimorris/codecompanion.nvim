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
      get_bufnr_from_filepath = function(path) return 42 end,
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
    package.loaded["codecompanion.strategies.chat.acp.fs"] = nil
    local fs = require("codecompanion.strategies.chat.acp.fs")

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
      get_bufnr_from_filepath = function(path) return nil end,
      write = function() error("should not be called") end,
    }

    package.loaded["codecompanion.utils.files"] = {
      write_to_path = function(path, content)
        _G._file_write = { path = path, content = content }
      end,
      read = function() return "" end,
    }

    vim.uv = vim.uv or {}
    package.loaded["codecompanion.strategies.chat.acp.fs"] = nil
    local fs = require("codecompanion.strategies.chat.acp.fs")

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
      get_bufnr_from_filepath = function(path) return 7 end,
      write = function(bufnr, content) error("boom") end,
    }

    package.loaded["codecompanion.utils.files"] = {
      write_to_path = function() end,
      read = function() return "" end,
    }

    vim.uv = vim.uv or {}
    package.loaded["codecompanion.strategies.chat.acp.fs"] = nil
    local fs = require("codecompanion.strategies.chat.acp.fs")

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
      get_bufnr_from_filepath = function(path) return nil end,
      write = function() end,
    }

    package.loaded["codecompanion.utils.files"] = {
      write_to_path = function(path, content) error("disk is full") end,
      read = function() return "" end,
    }

    vim.uv = vim.uv or {}
    package.loaded["codecompanion.strategies.chat.acp.fs"] = nil
    local fs = require("codecompanion.strategies.chat.acp.fs")

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

    package.loaded["codecompanion.strategies.chat.acp.fs"] = nil
    local fs = require("codecompanion.strategies.chat.acp.fs")

    local ok, data = fs.read_text_file("/no/such/file")
    return { ok = ok, data = data }
  ]])

  h.eq(false, result.ok)
  h.eq("ENOENT", result.data)
end

T["read_text_file returns full content, handles line and limit options"] = function()
  local result = child.lua([[
    -- Make uv.fs_stat report file exists
    vim.uv = { fs_stat = function(path) return { size = 123 } end }

    -- Provide read implementation returning predictable content
    local content = "first line\nsecond line\nthird"
    package.loaded["codecompanion.utils.files"] = {
      read = function(path) return content end,
    }

    package.loaded["codecompanion.strategies.chat.acp.fs"] = nil
    local fs = require("codecompanion.strategies.chat.acp.fs")

    local ok_all, all = fs.read_text_file("/some/path")
    local ok_line, from_line2 = fs.read_text_file("/some/path", { line = 2 })
    local ok_line0, from_line0 = fs.read_text_file("/some/path", { line = 0 })
    local ok_limit5, limit5 = fs.read_text_file("/some/path", { limit = 5 })
    local ok_limit2, limit2 = fs.read_text_file("/some/path", { limit = 2 })
    local ok_line2_lim1, line2lim1 = fs.read_text_file("/some/path", { line = 2, limit = 1 })
    local ok_limit0, limit0 = fs.read_text_file("/some/path", { limit = 0 })
    local ok_line4, line4 = fs.read_text_file("/some/path", { line = 4 })

    return {
      ok_all = ok_all, all = all,
      ok_line = ok_line, from_line2 = from_line2,
      ok_line0 = ok_line0, from_line0 = from_line0,
      ok_limit5 = ok_limit5, limit5 = limit5,
      ok_limit2 = ok_limit2, limit2 = limit2,
      ok_line2_lim1 = ok_line2_lim1, line2lim1 = line2lim1,
      ok_limit0 = ok_limit0, limit0 = limit0,
      ok_line4 = ok_line4, line4 = line4
    }
  ]])

  local full = "first line\nsecond line\nthird"

  h.is_true(result.ok_all)
  h.eq(full, result.all)

  -- line=2 should return from line 2 to EOF
  h.is_true(result.ok_line)
  h.eq("second line\nthird", result.from_line2)

  -- line=0 normalizes to 1 => full content
  h.is_true(result.ok_line0)
  h.eq(full, result.from_line0)

  -- limit=5 (more than number of lines) returns full content
  h.is_true(result.ok_limit5)
  h.eq(full, result.limit5)

  -- limit=2 returns first two lines
  h.is_true(result.ok_limit2)
  h.eq("first line\nsecond line", result.limit2)

  -- line=2, limit=1 returns only second line
  h.is_true(result.ok_line2_lim1)
  h.eq("second line", result.line2lim1)

  -- limit=0 returns empty string
  h.is_true(result.ok_limit0)
  h.eq("", result.limit0)

  -- start line beyond EOF returns empty string
  h.is_true(result.ok_line4)
  h.eq("", result.line4)
end

return T
