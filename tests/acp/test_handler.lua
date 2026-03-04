local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })

      child.lua([[
        -- Mock dependencies that the handler module requires
        package.loaded["codecompanion.config"] = {
          constants = { LLM_ROLE = "llm", USER_ROLE = "user" },
          display = { chat = { show_reasoning = false } },
        }
        package.loaded["codecompanion.utils.log"] = {
          debug = function() end,
          error = function() end,
        }
        package.loaded["codecompanion.interactions.chat.acp.formatters"] = {
          tool_message = function(tool_call)
            return (tool_call.kind or "tool") .. ": " .. (tool_call.title or "")
          end,
        }

        ACPHandler = require("codecompanion.interactions.chat.acp.handler")

        -- Create a minimal mock chat object
        function make_mock_chat()
          local chat = {
            bufnr = vim.api.nvim_create_buf(true, true),
            adapter = { opts = {} },
            status = nil,
            output = {},
            MESSAGE_TYPES = {
              LLM_MESSAGE = "llm_message",
              TOOL_MESSAGE = "tool_message",
              REASONING_MESSAGE = "reasoning_message",
            },
            done_called = false,
            done_args = {},
            checktime_buffers = {},
          }

          function chat:add_buf_message(msg, opts)
            return 1, "icon-1"
          end

          function chat:update_buf_line(line, content, opts)
          end

          function chat:done(output, reasoning, tools)
            self.done_called = true
            self.done_args = { output = output, reasoning = reasoning, tools = tools }
          end

          return chat
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["ACP Handler"] = new_set()

T["ACP Handler"]["initializes with empty modified_paths"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)
    return {
      has_modified_paths = handler.modified_paths ~= nil,
      is_empty = next(handler.modified_paths) == nil,
    }
  ]])

  h.eq(result.has_modified_paths, true)
  h.eq(result.is_empty, true)
end

T["ACP Handler"]["tracks paths from edit tool calls with locations"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)

    handler:process_tool_call({
      toolCallId = "tc-1",
      kind = "edit",
      title = "Edit file",
      status = "completed",
      locations = {
        { path = "/tmp/foo.lua" },
        { path = "/tmp/bar.lua" },
      },
      content = {},
    })

    return handler.modified_paths
  ]])

  h.eq(result["/tmp/foo.lua"], true)
  h.eq(result["/tmp/bar.lua"], true)
end

T["ACP Handler"]["tracks paths from edit tool calls with diff content"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)

    handler:process_tool_call({
      toolCallId = "tc-2",
      kind = "edit",
      title = "Edit file",
      status = "completed",
      content = {
        { type = "diff", path = "/tmp/diff_file.lua", oldText = "old", newText = "new" },
      },
    })

    return handler.modified_paths
  ]])

  h.eq(result["/tmp/diff_file.lua"], true)
end

T["ACP Handler"]["tracks paths from write tool calls"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)

    handler:process_tool_call({
      toolCallId = "tc-3",
      kind = "write",
      title = "Write file",
      status = "completed",
      locations = {
        { path = "/tmp/new_file.lua" },
      },
      content = {},
    })

    return handler.modified_paths
  ]])

  h.eq(result["/tmp/new_file.lua"], true)
end

T["ACP Handler"]["does not track paths from read tool calls"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)

    handler:process_tool_call({
      toolCallId = "tc-4",
      kind = "read",
      title = "Read file",
      status = "completed",
      locations = {
        { path = "/tmp/read_only.lua" },
      },
      content = {},
    })

    return { is_empty = next(handler.modified_paths) == nil }
  ]])

  h.eq(result.is_empty, true)
end

T["ACP Handler"]["does not track paths from execute tool calls"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)

    handler:process_tool_call({
      toolCallId = "tc-5",
      kind = "execute",
      title = "Run command",
      status = "completed",
      locations = {},
      content = {},
    })

    return { is_empty = next(handler.modified_paths) == nil }
  ]])

  h.eq(result.is_empty, true)
end

T["ACP Handler"]["accumulates paths across multiple tool calls"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)

    handler:process_tool_call({
      toolCallId = "tc-6",
      kind = "edit",
      title = "Edit first",
      status = "completed",
      locations = { { path = "/tmp/first.lua" } },
      content = {},
    })

    handler:process_tool_call({
      toolCallId = "tc-7",
      kind = "write",
      title = "Write second",
      status = "completed",
      locations = { { path = "/tmp/second.lua" } },
      content = {},
    })

    handler:process_tool_call({
      toolCallId = "tc-8",
      kind = "edit",
      title = "Edit first again",
      status = "completed",
      locations = { { path = "/tmp/first.lua" } },
      content = {},
    })

    local count = 0
    for _ in pairs(handler.modified_paths) do count = count + 1 end
    return {
      count = count,
      has_first = handler.modified_paths["/tmp/first.lua"] == true,
      has_second = handler.modified_paths["/tmp/second.lua"] == true,
    }
  ]])

  h.eq(result.count, 2)
  h.eq(result.has_first, true)
  h.eq(result.has_second, true)
end

T["ACP Handler Completion"] = new_set()

T["ACP Handler Completion"]["calls checktime for modified buffers on completion"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)

    -- Create a temp file and open it as a buffer
    local tmp = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({ "original content" }, tmp)
    vim.cmd("noautocmd edit " .. tmp)
    local bufnr = vim.fn.bufnr(tmp)

    -- Simulate an edit tool call that modified this file
    handler:process_tool_call({
      toolCallId = "tc-10",
      kind = "edit",
      title = "Edit file",
      status = "completed",
      locations = { { path = tmp } },
      content = {},
    })

    -- Write new content to the file on disk (simulating what Claude Code does)
    vim.fn.writefile({ "modified content" }, tmp)

    -- Trigger completion which should checktime the buffer
    handler:handle_completion("end_turn")

    -- After checktime, the buffer should reflect the new disk content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Cleanup
    vim.fn.delete(tmp)

    return {
      done_called = chat.done_called,
      status = chat.status,
      buffer_content = lines[1],
      modified_paths_cleared = next(handler.modified_paths) == nil,
    }
  ]])

  h.eq(result.done_called, true)
  h.eq(result.status, "success")
  h.eq(result.buffer_content, "modified content")
  h.eq(result.modified_paths_cleared, true)
end

T["ACP Handler Completion"]["skips checktime when no files were modified"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)

    -- No tool calls made, so modified_paths is empty
    handler:handle_completion("end_turn")

    return {
      done_called = chat.done_called,
      status = chat.status,
    }
  ]])

  h.eq(result.done_called, true)
  h.eq(result.status, "success")
end

T["ACP Handler Completion"]["skips checktime for paths without open buffers"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)

    -- Simulate edit of a file that is NOT open in a buffer
    handler:process_tool_call({
      toolCallId = "tc-11",
      kind = "edit",
      title = "Edit file",
      status = "completed",
      locations = { { path = "/tmp/not_open_anywhere_" .. os.time() .. ".lua" } },
      content = {},
    })

    -- Should not error even though no buffer matches
    handler:handle_completion("end_turn")

    return {
      done_called = chat.done_called,
      modified_paths_cleared = next(handler.modified_paths) == nil,
    }
  ]])

  h.eq(result.done_called, true)
  h.eq(result.modified_paths_cleared, true)
end

T["ACP Handler Completion"]["reloads multiple modified buffers"] = function()
  local result = child.lua([[
    local chat = make_mock_chat()
    local handler = ACPHandler.new(chat)

    -- Create two temp files and open them
    local tmp1 = vim.fn.tempname() .. "_1.lua"
    local tmp2 = vim.fn.tempname() .. "_2.lua"
    vim.fn.writefile({ "file1 original" }, tmp1)
    vim.fn.writefile({ "file2 original" }, tmp2)
    vim.cmd("noautocmd edit " .. tmp1)
    local bufnr1 = vim.fn.bufnr(tmp1)
    vim.cmd("noautocmd edit " .. tmp2)
    local bufnr2 = vim.fn.bufnr(tmp2)

    -- Simulate tool calls editing both files
    handler:process_tool_call({
      toolCallId = "tc-20",
      kind = "edit",
      title = "Edit first",
      status = "completed",
      locations = { { path = tmp1 } },
      content = {},
    })
    handler:process_tool_call({
      toolCallId = "tc-21",
      kind = "write",
      title = "Write second",
      status = "completed",
      locations = { { path = tmp2 } },
      content = {},
    })

    -- Modify both files on disk
    vim.fn.writefile({ "file1 modified" }, tmp1)
    vim.fn.writefile({ "file2 modified" }, tmp2)

    handler:handle_completion("end_turn")

    local lines1 = vim.api.nvim_buf_get_lines(bufnr1, 0, -1, false)
    local lines2 = vim.api.nvim_buf_get_lines(bufnr2, 0, -1, false)

    vim.fn.delete(tmp1)
    vim.fn.delete(tmp2)

    return {
      file1 = lines1[1],
      file2 = lines2[1],
    }
  ]])

  h.eq(result.file1, "file1 modified")
  h.eq(result.file2, "file2 modified")
end

return T
