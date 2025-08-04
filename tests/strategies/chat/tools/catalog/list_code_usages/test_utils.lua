local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Load the Utils module
        Utils = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.utils")

        -- Mock vim functions for testing
        _G.mock_state = {
          cwd = "/test/project",
          buffers = {},
          vim_calls = {}
        }

        -- Mock vim.fn.getcwd
        vim.fn.getcwd = function()
          return _G.mock_state.cwd
        end

        -- Mock vim.api.nvim_buf_is_valid
        vim.api.nvim_buf_is_valid = function(bufnr)
          if bufnr == nil then
            return false
          end
          return _G.mock_state.buffers[bufnr] ~= nil
        end

        -- Mock vim.api.nvim_get_option_value
        vim.api.nvim_get_option_value = function(option, opts)
          if option == "filetype" and opts.buf then
            local buffer = _G.mock_state.buffers[opts.buf]
            if buffer and buffer.filetype then
              return buffer.filetype
            end
            error("Buffer not found or no filetype")
          end
          error("Unknown option")
        end

        -- Mock vim.api.nvim_buf_get_name
        vim.api.nvim_buf_get_name = function(bufnr)
          local buffer = _G.mock_state.buffers[bufnr]
          if buffer and buffer.name then
            return buffer.name
          end
          error("Buffer not found or no name")
        end

        -- Mock vim.api.nvim_buf_get_lines
        vim.api.nvim_buf_get_lines = function(bufnr, start_row, end_row, strict_indexing)
          local buffer = _G.mock_state.buffers[bufnr]
          if buffer and buffer.lines then
            local lines = {}
            local actual_end = end_row == -1 and #buffer.lines or math.min(end_row, #buffer.lines)
            for i = start_row + 1, actual_end do
              lines[#lines + 1] = buffer.lines[i] or ""
            end
            return lines
          end
          error("Buffer not found or no lines")
        end

        -- Mock vim.cmd
        _G.original_vim_cmd = vim.cmd
        vim.cmd = function(cmd)
          _G.mock_state.vim_calls[#_G.mock_state.vim_calls + 1] = cmd
          if cmd:match("^edit ") then
            -- Simulate edit command success/failure
            if _G.mock_state.edit_should_fail then
              error("Edit failed")
            end
          elseif cmd == "normal! zz" then
            -- Center command, always succeeds
          else
            -- For other commands, call original
            _G.original_vim_cmd(cmd)
          end
        end

        -- Mock vim.api.nvim_win_set_cursor
        vim.api.nvim_win_set_cursor = function(winnr, pos)
          _G.mock_state.vim_calls[#_G.mock_state.vim_calls + 1] = {
            func = "nvim_win_set_cursor",
            winnr = winnr,
            pos = pos
          }
          if _G.mock_state.cursor_should_fail then
            error("Cursor set failed")
          end
        end

        -- Mock vim.fn.fnameescape
        vim.fn.fnameescape = function(filename)
          return "'" .. filename .. "'"
        end

        -- Helper to create mock buffer
        function create_mock_buffer(bufnr, name, filetype, lines)
          _G.mock_state.buffers[bufnr] = {
            name = name,
            filetype = filetype,
            lines = lines or {}
          }
        end

        -- Helper to reset mock state
        function reset_mock_state()
          _G.mock_state = {
            cwd = "/test/project",
            buffers = {},
            vim_calls = {},
            edit_should_fail = false,
            cursor_should_fail = false
          }
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["create_result"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["create_result"]["creates result with status and data"] = function()
  child.lua([[
    local result = Utils.create_result("success", "test data")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("success", result.status)
  h.eq("test data", result.data)
end

T["create_result"]["creates result with nil data"] = function()
  child.lua([[
    local result = Utils.create_result("error", nil)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("error", result.status)
  h.eq(nil, result.data)
end

T["uri_to_filepath"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["uri_to_filepath"]["converts file URI to filepath"] = function()
  child.lua([[
    local result = Utils.uri_to_filepath("file:///home/user/project/test.lua")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("/home/user/project/test.lua", result)
end

T["uri_to_filepath"]["handles URI without file protocol"] = function()
  child.lua([[
    local result = Utils.uri_to_filepath("/home/user/project/test.lua")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("/home/user/project/test.lua", result)
end

T["uri_to_filepath"]["handles nil URI"] = function()
  child.lua([[
    local result = Utils.uri_to_filepath(nil)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("", result)
end

T["uri_to_filepath"]["handles empty URI"] = function()
  child.lua([[
    local result = Utils.uri_to_filepath("")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("", result)
end

T["make_relative_path"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["make_relative_path"]["converts absolute path within project to relative"] = function()
  child.lua([[
    _G.mock_state.cwd = "/test/project"

    local result = Utils.make_relative_path("/test/project/src/main.lua")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("src/main.lua", result)
end

T["make_relative_path"]["handles path outside project"] = function()
  child.lua([[
    _G.mock_state.cwd = "/test/project"

    local result = Utils.make_relative_path("/other/project/file.lua")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("file.lua", result) -- Should return just filename
end

T["make_relative_path"]["handles Windows-style paths"] = function()
  child.lua([[
    _G.mock_state.cwd = "C:\\test\\project"

    local result = Utils.make_relative_path("C:\\test\\project\\src\\main.lua")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("src/main.lua", result) -- Should normalize to forward slashes
end

T["make_relative_path"]["handles nil filepath"] = function()
  child.lua([[
    local result = Utils.make_relative_path(nil)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("", result)
end

T["make_relative_path"]["handles empty filepath"] = function()
  child.lua([[
    local result = Utils.make_relative_path("")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("", result)
end

T["make_relative_path"]["handles cwd without trailing slash"] = function()
  child.lua([[
    _G.mock_state.cwd = "/test/project" -- No trailing slash

    local result = Utils.make_relative_path("/test/project/src/main.lua")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("src/main.lua", result)
end

T["is_in_project"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["is_in_project"]["returns true for file within project"] = function()
  child.lua([[
    _G.mock_state.cwd = "/test/project"

    local result = Utils.is_in_project("/test/project/src/main.lua")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result)
end

T["is_in_project"]["returns false for file outside project"] = function()
  child.lua([[
    _G.mock_state.cwd = "/test/project"

    local result = Utils.is_in_project("/other/project/file.lua")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(false, result)
end

T["is_in_project"]["handles exact project root path"] = function()
  child.lua([[
    _G.mock_state.cwd = "/test/project"

    local result = Utils.is_in_project("/test/project")

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result)
end

T["is_valid_buffer"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["is_valid_buffer"]["returns true for valid buffer"] = function()
  child.lua([[
    create_mock_buffer(1, "/test/file.lua", "lua")

    local result = Utils.is_valid_buffer(1)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result)
end

T["is_valid_buffer"]["returns false for invalid buffer"] = function()
  child.lua([[
    local result = Utils.is_valid_buffer(999)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(false, result)
end

T["is_valid_buffer"]["returns falsy for nil buffer"] = function()
  child.lua([[
    local result = Utils.is_valid_buffer(nil)

    _G.test_result = {
      result = result,
      is_falsy = not result
    }
  ]])

  local result = child.lua_get("_G.test_result")
  -- The function should return a falsy value (nil) for nil buffer
  h.eq(true, result.is_falsy)
end

T["safe_get_filetype"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["safe_get_filetype"]["returns filetype for valid buffer"] = function()
  child.lua([[
    create_mock_buffer(1, "/test/file.lua", "lua")

    local result = Utils.safe_get_filetype(1)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("lua", result)
end

T["safe_get_filetype"]["returns empty string for invalid buffer"] = function()
  child.lua([[
    local result = Utils.safe_get_filetype(999)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("", result)
end

T["safe_get_filetype"]["returns empty string when API call fails"] = function()
  child.lua([[
    create_mock_buffer(1, "/test/file.lua", nil) -- No filetype set

    local result = Utils.safe_get_filetype(1)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("", result)
end

T["safe_get_buffer_name"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["safe_get_buffer_name"]["returns name for valid buffer"] = function()
  child.lua([[
    create_mock_buffer(1, "/test/file.lua", "lua")

    local result = Utils.safe_get_buffer_name(1)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("/test/file.lua", result)
end

T["safe_get_buffer_name"]["returns empty string for invalid buffer"] = function()
  child.lua([[
    local result = Utils.safe_get_buffer_name(999)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("", result)
end

T["safe_get_buffer_name"]["returns empty string when API call fails"] = function()
  child.lua([[
    create_mock_buffer(1, nil, "lua") -- No name set

    local result = Utils.safe_get_buffer_name(1)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq("", result)
end

T["safe_get_lines"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["safe_get_lines"]["returns lines for valid buffer"] = function()
  child.lua([[
    create_mock_buffer(1, "/test/file.lua", "lua", {"line 1", "line 2", "line 3"})

    local result = Utils.safe_get_lines(1, 0, 2)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(2, #result)
  h.eq("line 1", result[1])
  h.eq("line 2", result[2])
end

T["safe_get_lines"]["returns all lines when end_row is -1"] = function()
  child.lua([[
    create_mock_buffer(1, "/test/file.lua", "lua", {"line 1", "line 2", "line 3"})

    local result = Utils.safe_get_lines(1, 0, -1)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(3, #result)
  h.eq("line 1", result[1])
  h.eq("line 2", result[2])
  h.eq("line 3", result[3])
end

T["safe_get_lines"]["returns empty table for invalid buffer"] = function()
  child.lua([[
    local result = Utils.safe_get_lines(999, 0, 2)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq({}, result)
end

T["safe_get_lines"]["returns empty table when API call fails"] = function()
  child.lua([[
    create_mock_buffer(1, "/test/file.lua", "lua", nil) -- No lines set

    local result = Utils.safe_get_lines(1, 0, 2)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq({}, result)
end

T["async_edit_file"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["async_edit_file"]["successfully opens file"] = function()
  child.lua([[
    local callback_called = false
    local callback_result = nil

    Utils.async_edit_file("/test/file.lua", function(success)
      callback_called = true
      callback_result = success
    end)

    vim.wait(100) -- Wait for async operation

    _G.test_result = {
      callback_called = callback_called,
      callback_result = callback_result,
      vim_calls = _G.mock_state.vim_calls
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq(true, result.callback_result)
  h.expect_tbl_contains("edit '/test/file.lua'", result.vim_calls)
end

T["async_edit_file"]["handles file open failure"] = function()
  child.lua([[
    _G.mock_state.edit_should_fail = true

    local callback_called = false
    local callback_result = nil

    Utils.async_edit_file("/nonexistent/file.lua", function(success)
      callback_called = true
      callback_result = success
    end)

    vim.wait(100) -- Wait for async operation

    _G.test_result = {
      callback_called = callback_called,
      callback_result = callback_result
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq(false, result.callback_result)
end

T["async_edit_file"]["escapes filename properly"] = function()
  child.lua([[
    local callback_called = false

    Utils.async_edit_file("/test/file with spaces.lua", function(success)
      callback_called = true
    end)

    vim.wait(100) -- Wait for async operation

    _G.test_result = {
      callback_called = callback_called,
      vim_calls = _G.mock_state.vim_calls
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.expect_tbl_contains("edit '/test/file with spaces.lua'", result.vim_calls)
end

T["async_set_cursor"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["async_set_cursor"]["successfully sets cursor position"] = function()
  child.lua([[
    local callback_called = false
    local callback_result = nil

    Utils.async_set_cursor(10, 5, function(success)
      callback_called = true
      callback_result = success
    end)

    vim.wait(100) -- Wait for async operation

    _G.test_result = {
      callback_called = callback_called,
      callback_result = callback_result,
      vim_calls = _G.mock_state.vim_calls
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq(true, result.callback_result)

  -- Check that cursor was set and screen was centered
  local cursor_call = nil
  for _, call in ipairs(result.vim_calls) do
    if type(call) == "table" and call.func == "nvim_win_set_cursor" then
      cursor_call = call
      break
    end
  end
  h.not_eq(nil, cursor_call)
  h.eq(0, cursor_call.winnr) -- Current window
  h.eq(10, cursor_call.pos[1])
  h.eq(5, cursor_call.pos[2])
  h.expect_tbl_contains("normal! zz", result.vim_calls) -- Screen centering
end

T["async_set_cursor"]["handles cursor set failure"] = function()
  child.lua([[
    _G.mock_state.cursor_should_fail = true

    local callback_called = false
    local callback_result = nil

    Utils.async_set_cursor(10, 5, function(success)
      callback_called = true
      callback_result = success
    end)

    vim.wait(100) -- Wait for async operation

    _G.test_result = {
      callback_called = callback_called,
      callback_result = callback_result,
      vim_calls = _G.mock_state.vim_calls
    }
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result.callback_called)
  h.eq(false, result.callback_result)
  -- Should not call "normal! zz" when cursor setting fails
  h.expect_truthy(not vim.tbl_contains(result.vim_calls, "normal! zz"))
end

T["is_enclosed_by"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[reset_mock_state()]])
    end,
  },
})

T["is_enclosed_by"]["returns true when block A is enclosed by block B"] = function()
  child.lua([[
    local block_a = {
      filename = "test.lua",
      start_line = 15,
      end_line = 20
    }

    local block_b = {
      filename = "test.lua",
      start_line = 10,
      end_line = 25
    }

    local result = Utils.is_enclosed_by(block_a, block_b)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result)
end

T["is_enclosed_by"]["returns false when blocks are in different files"] = function()
  child.lua([[
    local block_a = {
      filename = "test1.lua",
      start_line = 15,
      end_line = 20
    }

    local block_b = {
      filename = "test2.lua",
      start_line = 10,
      end_line = 25
    }

    local result = Utils.is_enclosed_by(block_a, block_b)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(false, result)
end

T["is_enclosed_by"]["returns false when block A extends beyond block B"] = function()
  child.lua([[
    local block_a = {
      filename = "test.lua",
      start_line = 5,
      end_line = 30
    }

    local block_b = {
      filename = "test.lua",
      start_line = 10,
      end_line = 25
    }

    local result = Utils.is_enclosed_by(block_a, block_b)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(false, result)
end

T["is_enclosed_by"]["returns true when blocks are identical"] = function()
  child.lua([[
    local block_a = {
      filename = "test.lua",
      start_line = 10,
      end_line = 20
    }

    local block_b = {
      filename = "test.lua",
      start_line = 10,
      end_line = 20
    }

    local result = Utils.is_enclosed_by(block_a, block_b)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(true, result)
end

T["is_enclosed_by"]["returns false when block A starts before block B"] = function()
  child.lua([[
    local block_a = {
      filename = "test.lua",
      start_line = 5,
      end_line = 15
    }

    local block_b = {
      filename = "test.lua",
      start_line = 10,
      end_line = 20
    }

    local result = Utils.is_enclosed_by(block_a, block_b)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(false, result)
end

T["is_enclosed_by"]["returns false when block A ends after block B"] = function()
  child.lua([[
    local block_a = {
      filename = "test.lua",
      start_line = 15,
      end_line = 25
    }

    local block_b = {
      filename = "test.lua",
      start_line = 10,
      end_line = 20
    }

    local result = Utils.is_enclosed_by(block_a, block_b)

    _G.test_result = result
  ]])

  local result = child.lua_get("_G.test_result")
  h.eq(false, result)
end

return T
