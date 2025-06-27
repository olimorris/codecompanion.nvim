local h = require("tests.helpers")

local expect = MiniTest.expect
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        codecompanion = require("codecompanion")
      ]])
    end,
    post_once = child.stop,
  },
})

T["extensions"] = new_set()

T["extensions"]["loads pure extension via setup()"] = function()
  -- First mock the extension module
  child.lua([[
    ---@type CodeCompanion.Extension
    package.loaded['codecompanion._extensions.test_extension'] = {
      setup = function(opts)
        require("codecompanion.config").strategies.chat.keymaps.test_keymap = {
          modes = { n = "gt" },
          description = "Test Keymap",
        }
      end,
      exports = {
        test_function = function()
          return "test_value"
        end
      }
    }
  ]])

  -- Now try loading it through setup
  child.lua([[
    codecompanion.setup({
      extensions = {
        test_extension = {
          enabled = true,
          opts = {
            test_option = true
          }
        }
      }
    })
  ]])

  h.eq(
    "function",
    child.lua_get([[
      type(codecompanion.extensions.test_extension.test_function)
    ]])
  )
end

T["extensions"]["loads external extension via setup()"] = function()
  child.lua([[
    ---@type CodeCompanion.Extension
    local mock_ext = {
      setup = function(opts)
        require("codecompanion.config").strategies.chat.keymaps.test_action = {
          modes = { n = "gt" },
          description = "Test Action",
        }
      end,
      exports = {
        test_function = function() return "test_value" end
      }
    }

    codecompanion.setup({
      extensions = {
        external_extension = {
          enabled = true,
          callback = mock_ext,  -- Pass extension directly as callback
          opts = {
            test_option = true
          }
        }
      }
    })
  ]])

  h.eq(
    "function",
    child.lua_get([[
      type(codecompanion.extensions.external_extension.test_function)
    ]])
  )
end

T["extensions"]["loads via register_extension()"] = function()
  child.lua([[
    -- Create extension with setup and exports
    ---@type CodeCompanion.Extension
    local extension = {
      setup = function()
        local chat_keymaps = require("codecompanion.config").strategies.chat.keymaps
        chat_keymaps.test_action = {
          modes = { n = "gt" },
          description = "Test Action",
        }
      end,
      exports = {
        test_function = function() return "dynamic" end
      }
    }

    codecompanion.register_extension("test_extension2", extension)
  ]])

  -- Verify extension exists in exports
  h.eq(
    "function",
    child.lua_get([[
      type(codecompanion.extensions.test_extension2.test_function)
    ]])
  )
end

T["extensions"]["has() returns true for extensions feature"] = function()
  h.eq(
    true,
    child.lua_get([[
      codecompanion.has("extensions")
    ]])
  )
end

T["extensions"]["respects enabled flag"] = function()
  child.lua([[
    ---@type CodeCompanion.Extension
    local mock_ext = {
      setup = function(opts) end,
      exports = {
        test_function = function() return "test_value" end
      }
    }

    codecompanion.setup({
      extensions = {
        disabled_extension = {
          enabled = false,
          callback = mock_ext
        }
      }
    })
  ]])

  -- Verify disabled extension returns nil
  h.eq(
    "nil",
    child.lua_get([[
      type(codecompanion.extensions.disabled_extension)
    ]])
  )
end

T["extensions"]["missing extensions return nil"] = function()
  -- Try accessing non-existent extension
  h.eq(
    "nil",
    child.lua_get([[
      type(codecompanion.extensions.nonexistent_extension)
    ]])
  )
end

return T
