local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Setup test directory
        _G.TEST_CWD = vim.fn.tempname()
        _G.TEST_DIR = 'tests/stubs/json_validation'
        _G.TEST_DIR_ABSOLUTE = vim.fs.joinpath(_G.TEST_CWD, _G.TEST_DIR)

        -- Create test directory structure
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE, 'p')

        _G.TEST_TMPFILE = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, "test.txt")

        h = require('tests.helpers')

        -- Setup chat buffer
        chat, tools = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.loop.fs_unlink, _G.TEST_TMPFILE)
        pcall(vim.fn.delete, _G.TEST_CWD, 'rf')
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["JSON Validation"] = new_set()

T["JSON Validation"]["rejects edits with missing oldText"] = function()
  child.lua([[
    -- Create test file
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = string.format('{"filepath": "%s", "edits": [{"newText": "replacement"}]}', _G.TEST_TMPFILE)
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("oldText", output)
end

T["JSON Validation"]["rejects edits with missing newText"] = function()
  child.lua([[
    -- Create test file
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "test"}]}', _G.TEST_TMPFILE)
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("newText", output)
end

T["JSON Validation"]["rejects edits with invalid replaceAll type"] = function()
  child.lua([[
    -- Create test file
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    -- Note: this test sends replaceAll as string "true" instead of boolean
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = vim.json.encode({
            filepath = _G.TEST_TMPFILE,
            edits = {
              { oldText = "test", newText = "replacement", replaceAll = "true" }
            }
          })
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("replaceAll", output)
end

T["JSON Validation"]["accepts valid edits"] = function()
  child.lua([[
    -- Create test file
    vim.fn.writefile({'test content'}, _G.TEST_TMPFILE)

    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = string.format(
            '{"filepath": "%s", "edits": [{"oldText": "test", "newText": "replaced", "replaceAll": false}]}',
            _G.TEST_TMPFILE
          )
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  -- Should succeed without validation errors
  local output = child.lua_get("chat.messages[#chat.messages].content")
  -- Check that it doesn't contain error messages
  h.eq(output:find("JSON argument validation failed"), nil, "Should not contain JSON validation error")
  h.eq(output:find("required"), nil, "Should not contain required field error")
end

T["JSON Validation"]["handles properly escaped quotes in code"] = function()
  child.lua([[
    -- Create test file with code that has quotes
    vim.fn.writefile({'function test() { return "hello"; }'}, _G.TEST_TMPFILE)

    -- Properly escaped JSON
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = string.format(
            '{"filepath": "%s", "edits": [{"oldText": "function test() { return \\"hello\\"; }", "newText": "function test() { return \\"world\\"; }", "replaceAll": false}]}',
            _G.TEST_TMPFILE
          )
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  -- Should succeed
  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq(output:find("JSON argument validation failed"), nil, "Should not contain validation error")

  -- Verify the file was actually edited
  local file_content = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(file_content, { 'function test() { return "world"; }' })
end

T["JSON Validation"]["provides helpful error for non-serializable values"] = function()
  child.lua([[
    -- Create test file
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    -- Create edits with invalid boolean type (string instead of boolean)
    local tool_args = {
      filepath = _G.TEST_TMPFILE,
      edits = {
        { 
          oldText = "test", 
          newText = "replaced",
          -- This should be boolean, not string
          replaceAll = "not_a_boolean"
        }
      }
    }

    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = vim.json.encode(tool_args)
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  -- Should get a validation error about replaceAll
  h.expect_contains("replaceAll", output)
end

T["JSON Validation"]["handles edits array with mixed valid and invalid entries"] = function()
  child.lua([[
    -- Create test file
    vim.fn.writefile({'line1', 'line2', 'line3'}, _G.TEST_TMPFILE)

    -- Second edit is missing newText
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = string.format(
            '{"filepath": "%s", "edits": [{"oldText": "line1", "newText": "replaced1", "replaceAll": false}, {"oldText": "line2"}]}',
            _G.TEST_TMPFILE
          )
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  -- Should identify the second edit as problematic
  h.expect_contains("Edit #2", output)
  h.expect_contains("newText", output)
end

T["JSON Validation"]["accepts empty strings for oldText and newText"] = function()
  child.lua([[
    -- Create empty file
    vim.fn.writefile({}, _G.TEST_TMPFILE)

    -- Empty oldText for empty file initialization
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = string.format(
            '{"filepath": "%s", "edits": [{"oldText": "", "newText": "new content", "replaceAll": false}]}',
            _G.TEST_TMPFILE
          )
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  -- Should succeed
  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.eq(output:find("JSON argument validation failed"), nil, "Should not contain validation error")
end

T["JSON Validation"]["detects non-serializable types (internal error)"] = function()
  child.lua([[
    -- Create test file
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    -- Manually construct tool args with a function deep in the structure
    -- This simulates an internal plugin bug (LLM would never send this)
    local tool_args = {
      filepath = _G.TEST_TMPFILE,
      edits = {
        {
          oldText = "test",
          newText = "replaced",
          replaceAll = false,
          -- Add a nested function (simulating internal error)
          _nested = { _fn = function() end }
        }
      }
    }

    -- Call the validation directly
    local init_module = require('codecompanion.strategies.chat.tools.catalog.insert_edit_into_file')
    local tool_func = init_module.cmds[1]
    
    local validation_result = nil
    tool_func(
      { chat = chat, tool = { opts = {} } },
      tool_args,
      nil,
      function(result)
        validation_result = result
      end
    )
    vim.wait(100)
    
    _G.validation_output = validation_result
  ]])

  local result = child.lua_get("_G.validation_output")
  h.eq(result.status, "error")
  -- Should mention invalid value type (user-friendly message for LLM)
  h.expect_contains("Invalid value type", result.data)
  -- Should mention valid JSON types
  h.expect_contains("valid JSON types", result.data)
end

T["JSON Validation"]["rejects oldText as number"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = vim.json.encode({
            filepath = _G.TEST_TMPFILE,
            edits = {
              { oldText = 123, newText = "replaced", replaceAll = false }
            }
          })
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("oldText", output)
  h.expect_contains("must be a string", output)
end

T["JSON Validation"]["rejects newText as boolean"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = vim.json.encode({
            filepath = _G.TEST_TMPFILE,
            edits = {
              { oldText = "test", newText = true, replaceAll = false }
            }
          })
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("newText", output)
  h.expect_contains("must be a string", output)
end

T["JSON Validation"]["rejects oldText as array"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = vim.json.encode({
            filepath = _G.TEST_TMPFILE,
            edits = {
              { oldText = {"array", "value"}, newText = "replaced", replaceAll = false }
            }
          })
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("oldText", output)
  h.expect_contains("must be a string", output)
  h.expect_contains("table", output)  -- Lua reports it as 'table'
end

T["JSON Validation"]["handles unescaped newline causing parse failure"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    -- Simulate LLM returning JSON with unescaped newline
    -- This will cause vim.json.decode to fail
    local invalid_json = '{"filepath": "' .. _G.TEST_TMPFILE .. '", "edits": [{"oldText": "line1\nline2", "newText": "replaced", "replaceAll": false}]}'
    
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = invalid_json
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  -- Should get error message from tools/init.lua error handling
  h.expect_contains("error", output:lower())
end

T["JSON Validation"]["handles unescaped quotes causing parse failure"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    -- Simulate LLM returning JSON with unescaped quotes inside string
    -- Note: We need to be careful with Lua string escaping here
    local invalid_json = '{"filepath": "' .. _G.TEST_TMPFILE .. '", "edits": [{"oldText": "say "hello"", "newText": "replaced", "replaceAll": false}]}'
    
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = invalid_json
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("error", output:lower())
end

T["JSON Validation"]["handles malformed JSON with missing comma"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    -- Missing comma between oldText and newText properties
    local invalid_json = '{"filepath": "' .. _G.TEST_TMPFILE .. '", "edits": [{"oldText": "test" "newText": "replaced", "replaceAll": false}]}'
    
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = invalid_json
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("error", output:lower())
end

T["JSON Validation"]["handles malformed JSON with trailing comma"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    -- Trailing comma after last property (invalid in strict JSON)
    local invalid_json = '{"filepath": "' .. _G.TEST_TMPFILE .. '", "edits": [{"oldText": "test", "newText": "replaced", "replaceAll": false,}]}'
    
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = invalid_json
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  -- Note: Some JSON parsers tolerate trailing commas, so this might not fail
  -- But we test it anyway to document the behavior
  if output:lower():find("error") then
    -- Parser rejected it
    h.expect_contains("error", output:lower())
  else
    -- Parser accepted it - just verify no crash
    h.eq(type(output), "string")
  end
end

T["JSON Validation"]["handles mismatched brackets"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    -- Missing closing bracket for edits array
    local invalid_json =
      string.format(
        '{"filepath": "%s", "edits": [{"oldText": "test", "newText": "replaced", "replaceAll": false}',
        _G.TEST_TMPFILE
      )  -- Missing ]}
    
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = invalid_json
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  h.expect_contains("error", output:lower())
end

T["JSON Validation"]["handles empty JSON string"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = ""
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  -- Empty string gets converted to {} by tools/init.lua, but should fail validation
  h.expect_contains("error", output:lower())
end

T["JSON Validation"]["handles null values in required fields"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    -- oldText is explicitly null (which is valid JSON but invalid for our schema)
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = vim.json.encode({
            filepath = _G.TEST_TMPFILE,
            edits = {
              { oldText = vim.NIL, newText = "replaced", replaceAll = false }
            }
          })
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  -- Should complain about oldText being wrong type or missing
  h.expect_contains("oldText", output)
end

T["JSON Validation"]["handles JSON with control characters"] = function()
  child.lua([[
    vim.fn.writefile({'test'}, _G.TEST_TMPFILE)

    -- Tab and other control characters that should be escaped
    local invalid_json = '{"filepath": "' .. _G.TEST_TMPFILE .. '", "edits": [{"oldText": "test\twith\ttab", "newText": "replaced", "replaceAll": false}]}'
    
    local tool = {
      {
        ["function"] = {
          name = "insert_edit_into_file",
          arguments = invalid_json
        },
      },
    }

    vim.g.codecompanion_yolo_mode = true
    tools:execute(chat, tool)
    vim.wait(100)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")
  -- This might succeed if parser handles tabs, just verify no crash
  h.eq(type(output), "string")
end

return T
