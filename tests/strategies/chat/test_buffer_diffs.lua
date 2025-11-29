local BufferDiffs = require("codecompanion.strategies.chat.buffer_diffs")
local h = require("tests.helpers")

local T = MiniTest.new_set()

T["BufferDiffs"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- Create a new buffer for each test
      vim.cmd("new")
      vim.bo.buftype = "nofile"
    end,
    post_case = function()
      -- Clean up after each test
      vim.cmd("bdelete!")
    end,
  },
})

T["BufferDiffs"]["creates new instance"] = function()
  local buffer_diffs = BufferDiffs.new()
  h.eq(type(buffer_diffs.buffers), "table")
  h.eq(vim.tbl_count(buffer_diffs.buffers), 0)
end

T["BufferDiffs"]["syncs a buffer"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  buffer_diffs:sync(bufnr)
  h.eq(type(buffer_diffs.buffers[bufnr]), "table")
  h.eq(type(buffer_diffs.buffers[bufnr].content), "table")
  h.eq(type(buffer_diffs.buffers[bufnr].changedtick), "number")
end

T["BufferDiffs"]["detects line modification"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
  })

  buffer_diffs:sync(bufnr)

  -- Modify line 2
  vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "modified line 2" })

  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(old_content[2], "line 2")
end

T["BufferDiffs"]["detects line deletion"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
  })

  buffer_diffs:sync(bufnr)

  -- Delete middle lines
  vim.api.nvim_buf_set_lines(bufnr, 1, 3, false, {})

  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(#old_content, 4)
  h.eq(old_content[2], "line 2")
  h.eq(old_content[3], "line 3")
end

T["BufferDiffs"]["detects multiple line deletion"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
  })

  buffer_diffs:sync(bufnr)

  -- Delete lines 2-4
  vim.api.nvim_buf_set_lines(bufnr, 1, 4, false, {})

  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(#old_content, 5)
  -- Verify the deleted lines were in the old content
  h.eq(old_content[2], "line 2")
  h.eq(old_content[3], "line 3")
  h.eq(old_content[4], "line 4")
end

T["BufferDiffs"]["detects multiple line insertion"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
  })

  buffer_diffs:sync(bufnr)

  -- Insert new lines between 1 and 2
  vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, {
    "new line 1",
    "new line 2",
    "new line 3",
  })

  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(#old_content, 2)
  h.eq(old_content[1], "line 1")
  h.eq(old_content[2], "line 2")
end

T["BufferDiffs"]["handles mixed operations"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
  })

  buffer_diffs:sync(bufnr)

  -- Replace lines 2-3 with three new lines
  vim.api.nvim_buf_set_lines(bufnr, 1, 3, false, {
    "new line 1",
    "new line 2",
    "new line 3",
  })

  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(old_content[2], "line 2")
  h.eq(old_content[3], "line 3")
end

T["BufferDiffs"]["handles unsyncing with buffer"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  buffer_diffs:sync(bufnr)
  h.not_eq(buffer_diffs.buffers[bufnr], nil)

  buffer_diffs:unsync(bufnr)
  h.eq(buffer_diffs.buffers[bufnr], nil)
end

T["BufferDiffs"]["ignores changes after unsyncing"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1" })
  buffer_diffs:sync(bufnr)
  buffer_diffs:unsync(bufnr)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified line 1" })

  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, false)
  h.eq(old_content, nil)
end

T["BufferDiffs"]["handles changes after buffer removal"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1" })
  buffer_diffs:sync(bufnr)

  vim.api.nvim_buf_delete(bufnr, {})

  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, true)
  h.eq(old_content, nil)
end

T["BufferDiffs"]["handles prepending to start of buffer"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
  })

  buffer_diffs:sync(bufnr)

  -- Prepend to start
  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new first line" })

  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(#old_content, 2)
  h.eq(old_content[1], "line 1")
end

T["BufferDiffs"]["handles appending to end of buffer"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
  })

  buffer_diffs:sync(bufnr)

  -- Append to end
  vim.api.nvim_buf_set_lines(bufnr, 2, 2, false, { "new last line" })

  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(#old_content, 2)
  h.eq(old_content[2], "line 2")
end

T["BufferDiffs"]["handles complete buffer replacement"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "old line 1",
    "old line 2",
  })

  buffer_diffs:sync(bufnr)

  -- Replace everything
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "new line 1",
    "new line 2",
    "new line 3",
  })

  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(old_content[1], "old line 1")
  h.eq(old_content[2], "old line 2")
end

T["BufferDiffs"]["handles no changes"] = function()
  local buffer_diffs = BufferDiffs.new()
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
  })

  buffer_diffs:sync(bufnr)

  -- No changes made
  local has_changed, old_content = buffer_diffs:get_changes(bufnr)
  h.eq(has_changed, false)
  h.eq(old_content, nil)
end

T["BufferDiffs"]["handles buffer deletion properly"] = function()
  local buffer_diffs = BufferDiffs.new()

  vim.cmd("new")
  local temp_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, { "test line 1", "test line 2" })

  buffer_diffs:sync(temp_buf)
  h.not_eq(buffer_diffs.buffers[temp_buf], nil)

  local has_changed, old_content = buffer_diffs:get_changes(temp_buf)
  h.eq(has_changed, false)
  h.eq(old_content, nil)

  vim.api.nvim_buf_delete(temp_buf, { force = true })

  h.eq(buffer_diffs.buffers[temp_buf], nil)
end

T["BufferDiffs"]["doesn't sync invalid buffers"] = function()
  local buffer_diffs = BufferDiffs.new()

  -- Create and immediately delete a buffer
  vim.cmd("new")
  local temp_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_delete(temp_buf, { force = true })

  buffer_diffs:sync(temp_buf)

  h.eq(buffer_diffs.buffers[temp_buf], nil)

  local has_changed, old_content = buffer_diffs:get_changes(temp_buf)
  h.eq(has_changed, false)
  h.eq(old_content, nil)
end

return T
