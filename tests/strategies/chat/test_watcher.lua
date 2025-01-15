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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  -- Check for modification type and content
  local found_modification = false
  for _, change in ipairs(changes) do
    if change.type == "modify" then
      h.eq(change.old_lines[1], "line 2", "Old line content should match")
      h.eq(change.new_lines[1], "modified line 2", "New line content should match")
      h.eq(change.start, 2, "Modification should be at line 2")
      found_modification = true
      break
    end
  end
  h.eq(found_modification, true, "Should detect line modification")
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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  -- We expect modifications for existing line positions and additions for new lines
  local modifications = 0
  local additions = 0

  for _, change in ipairs(changes) do
    if change.type == "modify" then
      if modifications == 0 then
        h.eq(change.old_lines[1], "line 2")
        h.eq(change.new_lines[1], "new line 1")
      elseif modifications == 1 then
        h.eq(change.old_lines[1], "line 3")
        h.eq(change.new_lines[1], "new line 2")
      end
      modifications = modifications + 1
    elseif change.type == "add" then
      h.eq(change.lines[1], "new line 3")
      additions = additions + 1
    end
  end

  h.eq(modifications, 2, "Should detect two modifications")
  h.eq(additions, 1, "Should detect one addition")
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

  local changes = watcher:get_changes(bufnr)
  h.eq(changes, nil)
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

  local changes = watcher:get_changes(bufnr)
  h.not_eq(changes, nil)

  local modifications = 0
  local additions = 0

  for _, change in ipairs(changes) do
    if change.type == "modify" then
      if modifications == 0 then
        h.eq(change.old_lines[1], "old line 1")
        h.eq(change.new_lines[1], "new line 1")
      elseif modifications == 1 then
        h.eq(change.old_lines[1], "old line 2")
        h.eq(change.new_lines[1], "new line 2")
      end
      modifications = modifications + 1
    elseif change.type == "add" then
      h.eq(change.lines[1], "new line 3")
      additions = additions + 1
    end
  end

  h.eq(modifications, 2, "Should detect modifications of existing lines")
  h.eq(additions, 1, "Should detect addition of new line")
end

T["Watchers"]["handles modifications after buffer switching"] = function()
  local watcher = Watcher.new()
  local main_buf = vim.api.nvim_get_current_buf()

  -- Initial state
  vim.api.nvim_buf_set_lines(main_buf, 0, -1, false, {
    "line 1",
    "line 2",
    "line 3",
    "line 4",
  })

  watcher:watch(main_buf)

  -- First modification
  vim.api.nvim_buf_set_lines(main_buf, 1, 3, false, {
    "modified line 2",
    "new line between",
    "modified line 3",
  })

  -- Get and process first changes
  local first_changes = watcher:get_changes(main_buf)

  -- Switch buffers
  vim.cmd("new")
  local temp_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, { "temporary buffer" })
  vim.api.nvim_set_current_buf(main_buf)

  -- Make new changes
  vim.api.nvim_buf_set_lines(main_buf, 1, 4, false, {
    "modified again line 2",
    "modified new line between",
  })

  local changes = watcher:get_changes(main_buf)
  h.not_eq(changes, nil)

  local found_modifications = 0
  local found_deletion = false

  for _, change in ipairs(changes) do
    if change.type == "modify" then
      if change.old_lines[1] == "modified line 2" and change.new_lines[1] == "modified again line 2" then
        found_modifications = found_modifications + 1
      elseif change.old_lines[1] == "new line between" and change.new_lines[1] == "modified new line between" then
        found_modifications = found_modifications + 1
      end
    elseif change.type == "delete" then
      if vim.tbl_contains(change.lines, "modified line 3") then
        found_deletion = true
      end
    end
  end

  h.eq(found_modifications, 2, "Should detect both line modifications from last known state")
  h.eq(found_deletion, true, "Should detect deletion from last known state")

  -- Clean up
  vim.api.nvim_buf_delete(temp_buf, { force = true })
end

T["Watchers"]["handles buffer deletion properly"] = function()
  local watcher = Watcher.new()

  vim.cmd("new")
  local temp_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, { "test line 1", "test line 2" })

  watcher:watch(temp_buf)
  h.not_eq(watcher.buffers[temp_buf], nil)

  local initial_changes = watcher:get_changes(temp_buf)
  h.eq(initial_changes, nil)

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

  local changes = watcher:get_changes(temp_buf)
  h.eq(changes, nil)
end

return T
