local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
    post_case = function()
      -- Cleanup test files
      child.lua([[
        if vim.fn.isdirectory('test_patch_dir') == 1 then
          vim.fn.delete('test_patch_dir', 'rf')
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Apply Patch"] = new_set()
T["Apply Patch"]["can parse patch text"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    local patch_text = [[
*** Begin Patch
*** Add File: test_patch.txt
+hello world
*** End Patch
    ]]
    local result = apply_patch.parse_patch(patch_text)
    _G.result = result
  ]=])

  h.eq(1, child.lua_get("#_G.result.hunks"))
  h.eq("add", child.lua_get("_G.result.hunks[1].type"))
  h.eq("test_patch.txt", child.lua_get("_G.result.hunks[1].path"))
  h.eq("hello world", child.lua_get("_G.result.hunks[1].contents"))
end

T["Apply Patch"]["can parse update patch text"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    local patch_text = [[
*** Begin Patch
*** Update File: test_update.txt
@@ context
-old line
+new line
*** End Patch
    ]]
    local result = apply_patch.parse_patch(patch_text)
    _G.result = result
  ]=])

  h.eq(1, child.lua_get("#_G.result.hunks"))
  h.eq("update", child.lua_get("_G.result.hunks[1].type"))
  h.eq("test_update.txt", child.lua_get("_G.result.hunks[1].path"))
  h.eq(1, child.lua_get("#_G.result.hunks[1].chunks"))
  h.eq("context", child.lua_get("_G.result.hunks[1].chunks[1].change_context"))
  h.eq("old line", child.lua_get("_G.result.hunks[1].chunks[1].old_lines[1]"))
  h.eq("new line", child.lua_get("_G.result.hunks[1].chunks[1].new_lines[1]"))
end

T["Apply Patch"]["can add a file"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    local patch_text = [[
*** Begin Patch
*** Add File: test_patch_dir/new_file.txt
+hello world
*** End Patch
    ]]
    local result = apply_patch.cmds[1](apply_patch, { patchText = patch_text }, nil)
    _G.result = result
    _G.file_exists = vim.fn.getfsize('test_patch_dir/new_file.txt') ~= -1
    
    local f = io.open('test_patch_dir/new_file.txt', 'r')
    _G.file_content = f:read('*a')
    f:close()
  ]=])

  h.eq("success", child.lua_get("_G.result.status"))
  h.eq(true, child.lua_get("_G.file_exists"))
  h.eq("hello world", child.lua_get("_G.file_content"))
end

T["Apply Patch"]["can delete a file"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    -- Setup: create file to delete
    vim.fn.mkdir('test_patch_dir', 'p')
    local f = io.open('test_patch_dir/delete_me.txt', 'w')
    f:write('bye')
    f:close()

    local patch_text = [[
*** Begin Patch
*** Delete File: test_patch_dir/delete_me.txt
*** End Patch
    ]]
    local result = apply_patch.cmds[1](apply_patch, { patchText = patch_text }, nil)
    _G.result = result
    _G.file_exists = vim.fn.getfsize('test_patch_dir/delete_me.txt') ~= -1
  ]=])

  h.eq("success", child.lua_get("_G.result.status"))
  h.eq(false, child.lua_get("_G.file_exists"))
end

T["Apply Patch"]["can update a file"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    -- Setup: create file to update
    vim.fn.mkdir('test_patch_dir', 'p')
    local f = io.open('test_patch_dir/update_me.txt', 'w')
    f:write("line 1\nline 2\nline 3\n")
    f:close()

    local patch_text = [[
*** Begin Patch
*** Update File: test_patch_dir/update_me.txt
@@ context
-line 2
+updated line 2
*** End Patch
    ]]
    local result = apply_patch.cmds[1](apply_patch, { patchText = patch_text }, nil)
    _G.result = result
    
    local f = io.open('test_patch_dir/update_me.txt', 'r')
    _G.file_content = f:read('*a')
    f:close()
  ]=])

  h.eq("success", child.lua_get("_G.result.status"))
  h.eq("line 1\nupdated line 2\nline 3\n", child.lua_get("_G.file_content"))
end

T["Apply Patch"]["can update and move a file"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    -- Setup: create file to update and move
    vim.fn.mkdir('test_patch_dir', 'p')
    local f = io.open('test_patch_dir/old_name.txt', 'w')
    f:write("old content\n")
    f:close()

    local patch_text = [[
*** Begin Patch
*** Update File: test_patch_dir/old_name.txt
*** Move to: test_patch_dir/new_name.txt
@@ context
-old content
+new content
*** End Patch
    ]]
    local result = apply_patch.cmds[1](apply_patch, { patchText = patch_text }, nil)
    _G.result = result
    _G.old_exists = vim.fn.getfsize('test_patch_dir/old_name.txt') ~= -1
    _G.new_exists = vim.fn.getfsize('test_patch_dir/new_name.txt') ~= -1
    
    local f = io.open('test_patch_dir/new_name.txt', 'r')
    _G.new_content = f:read('*a')
    f:close()
  ]=])

  h.eq("success", child.lua_get("_G.result.status"))
  h.eq(false, child.lua_get("_G.old_exists"))
  h.eq(true, child.lua_get("_G.new_exists"))
  h.eq("new content\n", child.lua_get("_G.new_content"))
end

T["Apply Patch"]["fails if file to update does not exist"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    local patch_text = [[
*** Begin Patch
*** Update File: non_existent.txt
@@ context
-old
+new
*** End Patch
    ]]
    local result = apply_patch.cmds[1](apply_patch, { patchText = patch_text }, nil)
    _G.result = result
  ]=])

  h.eq("error", child.lua_get("_G.result.status"))
  h.expect_starts_with("File to update does not exist", child.lua_get("_G.result.data"))
end

T["Apply Patch"]["can delete a file"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    -- Setup: create file to delete
    vim.fn.mkdir('test_patch_dir', 'p')
    local f = io.open('test_patch_dir/delete_me.txt', 'w')
    f:write('bye')
    f:close()

    local patch_text = [[
*** Begin Patch
*** Delete File: test_patch_dir/delete_me.txt
*** End Patch
    ]]
    local result = apply_patch.cmds[1](apply_patch, { patchText = patch_text }, nil)
    _G.result = result
    _G.file_exists = vim.fn.getfsize('test_patch_dir/delete_me.txt') ~= -1
  ]=])

  h.eq("success", child.lua_get("_G.result.status"))
  h.eq(false, child.lua_get("_G.file_exists"))
end

T["Apply Patch"]["can update a file"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    -- Setup: create file to update
    vim.fn.mkdir('test_patch_dir', 'p')
    local f = io.open('test_patch_dir/update_me.txt', 'w')
    f:write("line 1\nline 2\nline 3\n")
    f:close()

    local patch_text = [[
*** Begin Patch
*** Update File: test_patch_dir/update_me.txt
@@ context
-line 2
+updated line 2
*** End Patch
    ]]
    local result = apply_patch.cmds[1](apply_patch, { patchText = patch_text }, nil)
    _G.result = result
    
    local f = io.open('test_patch_dir/update_me.txt', 'r')
    _G.file_content = f:read('*a')
    f:close()
  ]=])

  h.eq("success", child.lua_get("_G.result.status"))
  h.eq("line 1\nupdated line 2\nline 3\n", child.lua_get("_G.file_content"))
end

T["Apply Patch"]["can update and move a file"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    -- Setup: create file to update and move
    vim.fn.mkdir('test_patch_dir', 'p')
    local f = io.open('test_patch_dir/old_name.txt', 'w')
    f:write("old content\n")
    f:close()

    local patch_text = [[
*** Begin Patch
*** Update File: test_patch_dir/old_name.txt
*** Move to: test_patch_dir/new_name.txt
@@ context
-old content
+new content
*** End Patch
    ]]
    local result = apply_patch.cmds[1](apply_patch, { patchText = patch_text }, nil)
    _G.result = result
    _G.old_exists = vim.fn.getfsize('test_patch_dir/old_name.txt') ~= -1
    _G.new_exists = vim.fn.getfsize('test_patch_dir/new_name.txt') ~= -1
    
    local f = io.open('test_patch_dir/new_name.txt', 'r')
    _G.new_content = f:read('*a')
    f:close()
  ]=])

  h.eq("success", child.lua_get("_G.result.status"))
  h.eq(false, child.lua_get("_G.old_exists"))
  h.eq(true, child.lua_get("_G.new_exists"))
  h.eq("new content\n", child.lua_get("_G.new_content"))
end

T["Apply Patch"]["fails if file to update does not exist"] = function()
  child.lua([=[
    local apply_patch = require('codecompanion.interactions.chat.tools.builtin.apply_patch')
    local patch_text = [[
*** Begin Patch
*** Update File: non_existent.txt
@@ context
-old
+new
*** End Patch
    ]]
    local result = apply_patch.cmds[1](apply_patch, { patchText = patch_text }, nil)
    _G.result = result
  ]=])

  h.eq("error", child.lua_get("_G.result.status"))
  h.expect_starts_with("File to update does not exist", child.lua_get("_G.result.data"))
end

return T
