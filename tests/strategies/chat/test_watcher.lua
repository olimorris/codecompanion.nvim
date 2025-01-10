local Watcher = require("codecompanion.strategies.chat.watcher")
local h = require("tests.helpers")

local T = MiniTest.new_set()

T["Watcher"] = MiniTest.new_set({
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

T["Watcher"]["creates new instance"] = function()
  local watcher = Watcher.new()
  h.eq(type(watcher.buffers), "table")
  h.eq(vim.tbl_count(watcher.buffers), 0)
end

T["Watcher"]["watches buffer"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  watcher:watch(bufnr)
  h.eq(type(watcher.buffers[bufnr]), "table")
  h.eq(type(watcher.buffers[bufnr].content), "table")
  h.eq(type(watcher.buffers[bufnr].changedtick), "number")
end

T["Watcher"]["detects line modification"] = function()
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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)
  -- Check that we have the change, don't care about internal representation
  local found_change = false
  for _, change in ipairs(changes) do
    if vim.tbl_contains(change.lines, "modified line 2") then
      found_change = true
      break
    end
  end
  h.eq(found_change, true)
end

T["Watcher"]["detects line deletion"] = function()
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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  -- Verify deleted content is captured
  local found_deletion = false
  for _, change in ipairs(changes) do
    if
      change.type == "delete"
      and vim.tbl_contains(change.lines, "line 2")
      and vim.tbl_contains(change.lines, "line 3")
    then
      found_deletion = true
      break
    end
  end
  h.eq(found_deletion, true)
end

T["Watcher"]["detects multiple line deletion"] = function()
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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  -- Verify all deleted lines are captured
  local found_deletion = false
  for _, change in ipairs(changes) do
    if
      change.type == "delete"
      and vim.tbl_contains(change.lines, "line 2")
      and vim.tbl_contains(change.lines, "line 3")
      and vim.tbl_contains(change.lines, "line 4")
    then
      found_deletion = true
      h.eq(#change.lines, 3, "Should have captured exactly 3 deleted lines")
      h.eq(change.start, 2, "Deletion should start at line 2")
      h.eq(change.end_line, 4, "Deletion should end at line 4")
      break
    end
  end
  h.eq(found_deletion, true, "Should have found the deletion of multiple lines")
end

T["Watcher"]["detects multiple line insertion"] = function()
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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  -- Verify all inserted lines are captured
  local found_insertion = false
  for _, change in ipairs(changes) do
    if
      change.type == "add"
      and vim.tbl_contains(change.lines, "new line 1")
      and vim.tbl_contains(change.lines, "new line 2")
      and vim.tbl_contains(change.lines, "new line 3")
    then
      found_insertion = true
      h.eq(#change.lines, 3, "Should have captured exactly 3 inserted lines")
      h.eq(change.start, 2, "Insertion should start at line 2")
      h.eq(change.end_line, 4, "Insertion should end at line 4")
      break
    end
  end
  h.eq(found_insertion, true, "Should have found the insertion of multiple lines")
end

T["Watcher"]["handles mixed operations"] = function()
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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  -- Verify both deletion and insertion are captured
  local found_deletion = false
  local found_insertion = false

  for _, change in ipairs(changes) do
    if
      change.type == "delete"
      and vim.tbl_contains(change.lines, "line 2")
      and vim.tbl_contains(change.lines, "line 3")
    then
      found_deletion = true
    elseif
      change.type == "add"
      and vim.tbl_contains(change.lines, "new line 1")
      and vim.tbl_contains(change.lines, "new line 2")
      and vim.tbl_contains(change.lines, "new line 3")
    then
      found_insertion = true
    end
  end

  h.eq(found_deletion, true, "Should have found the deletion")
  h.eq(found_insertion, true, "Should have found the insertion")
end

T["Watcher"]["handles unwatching buffer"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  watcher:watch(bufnr)
  h.not_eq(watcher.buffers[bufnr], nil)

  watcher:unwatch(bufnr)
  h.eq(watcher.buffers[bufnr], nil)
end

T["Watcher"]["ignores changes after unwatching"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line 1" })
  watcher:watch(bufnr)
  watcher:unwatch(bufnr)

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "modified line 1" })

  local changes = watcher:get_changes(bufnr)
  h.eq(changes, nil)
end

T["Watcher"]["handles empty buffer"] = function()
  local watcher = Watcher.new()
  local bufnr = vim.api.nvim_get_current_buf()

  watcher:watch(bufnr)

  -- Add content to empty buffer
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "new line" })

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  local found_addition = false
  for _, change in ipairs(changes) do
    if vim.tbl_contains(change.lines, "new line") then
      found_addition = true
      break
    end
  end
  h.eq(found_addition, true)
end

T["Watcher"]["handles prepending to start of buffer"] = function()
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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  local found_addition = false
  for _, change in ipairs(changes) do
    if change.type == "add" and change.lines[1] == "new first line" then
      found_addition = true
      h.eq(change.start, 1, "Should be added at beginning")
      break
    end
  end
  h.eq(found_addition, true, "Should detect addition at buffer start")
end

T["Watcher"]["handles appending to end of buffer"] = function()
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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  local found_addition = false
  for _, change in ipairs(changes) do
    if change.type == "add" and change.lines[1] == "new last line" then
      found_addition = true
      h.eq(change.start, 3, "Should be added at correct line number")
      break
    end
  end
  h.eq(found_addition, true, "Should detect addition at buffer end")
end

T["Watcher"]["handles complete buffer replacement"] = function()
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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  local found_deletion = false
  local found_addition = false

  for _, change in ipairs(changes) do
    if change.type == "delete" and vim.tbl_contains(change.lines, "old line 1") then
      found_deletion = true
    elseif change.type == "add" and vim.tbl_contains(change.lines, "new line 1") then
      found_addition = true
    end
  end

  h.eq(found_deletion, true, "Should detect deletion of old content")
  h.eq(found_addition, true, "Should detect addition of new content")
end

return T
