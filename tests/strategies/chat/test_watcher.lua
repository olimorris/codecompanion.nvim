local Watcher = require("codecompanion.strategies.chat.watchers")
local h = require("tests.helpers")

local T = MiniTest.new_set()

T["Watchers"] = MiniTest.new_set({
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

T["Watchers"]["creates new instance"] = function()
  local watcher = Watcher.new()
  h.eq(type(watcher.buffers), "table")
  h.eq(vim.tbl_count(watcher.buffers), 0)
end

T["Watchers"]["watches buffer"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  watcher:watch(bufnr)
  h.eq(type(watcher.buffers[bufnr]), "table")
  h.eq(type(watcher.buffers[bufnr].content), "table")
  h.eq(type(watcher.buffers[bufnr].changedtick), "number")
end

T["Watchers"]["detects line modification"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
  })

  watcher:watch(bufnr)

  -- Modify line 2
  vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "modified line 2" })

  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(old_content[2], "line 2")
end

T["Watchers"]["detects line deletion"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
  })

  watcher:watch(bufnr)

  -- Delete middle lines
  vim.api.nvim_buf_set_lines(bufnr, 1, 3, false, {})

  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(#old_content, 4)
  h.eq(old_content[2], "line 2")
  h.eq(old_content[3], "line 3")
end

T["Watchers"]["detects multiple line deletion"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
    "line 5",
  })

  watcher:watch(bufnr)

  -- Delete lines 2-4
  vim.api.nvim_buf_set_lines(bufnr, 1, 4, false, {})

  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(#old_content, 5)
  -- Verify the deleted lines were in the old content
  h.eq(old_content[2], "line 2")
  h.eq(old_content[3], "line 3")
  h.eq(old_content[4], "line 4")
end

T["Watchers"]["detects multiple line insertion"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
  })

  watcher:watch(bufnr)

  -- Insert new lines between 1 and 2
  vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, {
    "new line 1",
    "new line 2",
    "new line 3",
  })

  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(#old_content, 2)
  h.eq(old_content[1], "line 1")
  h.eq(old_content[2], "line 2")
end

T["Watchers"]["handles mixed operations"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
  })

  watcher:watch(bufnr)

  -- Replace lines 2-3 with three new lines
  vim.api.nvim_buf_set_lines(bufnr, 1, 3, false, {
    "new line 1",
    "new line 2",
    "new line 3",
  })

  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(old_content[2], "line 2")
  h.eq(old_content[3], "line 3")
end

T["Watchers"]["handles unwatching buffer"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  watcher:watch(bufnr)
  h.not_eq(watcher.buffers[bufnr], nil)

  watcher:unwatch(bufnr)
  h.eq(watcher.buffers[bufnr], nil)
end

T["Watchers"]["ignores changes after unwatching"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1" })
  watcher:watch(bufnr)
  watcher:unwatch(bufnr)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified line 1" })

  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, false)
  h.eq(old_content, nil)
end

T["Watchers"]["handles changes after buffer removal"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1" })
  watcher:watch(bufnr)

  vim.api.nvim_buf_delete(bufnr, {})

  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, true)
  h.eq(old_content, nil)
end

T["Watchers"]["handles prepending to start of buffer"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
  })

  watcher:watch(bufnr)

  -- Prepend to start
  vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new first line" })

  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(#old_content, 2)
  h.eq(old_content[1], "line 1")
end

T["Watchers"]["handles appending to end of buffer"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
  })

  watcher:watch(bufnr)

  -- Append to end
  vim.api.nvim_buf_set_lines(bufnr, 2, 2, false, { "new last line" })

  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(#old_content, 2)
  h.eq(old_content[2], "line 2")
end

T["Watchers"]["handles complete buffer replacement"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  -- Set initial content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "old line 1",
    "old line 2",
  })

  watcher:watch(bufnr)

  -- Replace everything
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "new line 1",
    "new line 2",
    "new line 3",
  })

  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, true)
  h.not_eq(old_content, nil)
  h.eq(old_content[1], "old line 1")
  h.eq(old_content[2], "old line 2")
end

T["Watchers"]["handles no changes"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "line 1",
    "line 2",
  })

  watcher:watch(bufnr)

  -- No changes made
  local has_changed, old_content = watcher:get_changes(bufnr)
  h.eq(has_changed, false)
  h.eq(old_content, nil)
end

T["Watchers"]["handles buffer deletion properly"] = function()
  local watcher = Watcher.new()

  vim.cmd("new")
  local temp_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, { "test line 1", "test line 2" })

  watcher:watch(temp_buf)
  h.not_eq(watcher.buffers[temp_buf], nil)

  local has_changed, old_content = watcher:get_changes(temp_buf)
  h.eq(has_changed, false)
  h.eq(old_content, nil)

  vim.api.nvim_buf_delete(temp_buf, { force = true })

  h.eq(watcher.buffers[temp_buf], nil)
end

T["Watchers"]["doesn't watch invalid buffers"] = function()
  local watcher = Watcher.new()

  -- Create and immediately delete a buffer
  vim.cmd("new")
  local temp_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_delete(temp_buf, { force = true })

  watcher:watch(temp_buf)

  h.eq(watcher.buffers[temp_buf], nil)

  local has_changed, old_content = watcher:get_changes(temp_buf)
  h.eq(has_changed, false)
  h.eq(old_content, nil)
end

return T
