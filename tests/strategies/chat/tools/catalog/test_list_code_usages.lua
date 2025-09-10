local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)

      child.lua([[
        -- Prepare temp project structure
        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()

        -- Ensure the tool can switch back to the user's window
        chat.buffer_context.winnr = vim.api.nvim_get_current_win()

        _G.PROJ_DIR = vim.fs.joinpath(vim.fn.tempname(), "cc_lcu_proj")
        vim.fn.mkdir(vim.fs.joinpath(_G.PROJ_DIR, "src"), "p")

        _G.MODULE_PATH = vim.fs.joinpath(_G.PROJ_DIR, "src", "module.lua")
        _G.USAGE_PATH  = vim.fs.joinpath(_G.PROJ_DIR, "src", "usage.lua")

        -- Write files
        local module_lines = {
          "local M = {}",
          "",
          "--- My function docs",
          "function M.my_func(x)",
          "  return x + 1",
          "end",
          "",
          "return M",
        }
        vim.fn.writefile(module_lines, _G.MODULE_PATH)

        local usage_lines = {
          "local M = require('module')",
          "",
          "local a = M.my_func(41)",
          "print(M.my_func(1))",
        }
        vim.fn.writefile(usage_lines, _G.USAGE_PATH)

        -- Enter project dir for relative paths in output
        vim.cmd('cd ' .. _G.PROJ_DIR)

        -- Open a lua buffer to ensure filetype detection later
        vim.cmd('edit ' .. vim.fn.fnameescape(_G.MODULE_PATH))
      ]])

      -- Mock SymbolFinder: return one symbol at the function definition, no grep
      child.lua([[
        local SF = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.symbol_finder")
        SF.find_with_lsp_async = function(symbolName, filepaths, cb)
          cb({
            {
              file = _G.MODULE_PATH,
              name = symbolName,
              range = {
                start = { line = 3, character = 0 }, -- zero-indexed (points to `function M.my_func`)
                ["end"] = { line = 5, character = 3 },
              },
            },
          })
        end
        SF.find_with_grep_async = function(_, _, _, cb)
          cb(nil)
        end
      ]])

      -- Mock LspHandler: synthesize results for definition, references, documentation
      child.lua([[
        local LH = require("codecompanion.strategies.chat.tools.catalog.list_code_usages.lsp_handler")
        local Methods = vim.lsp.protocol.Methods

        LH.execute_request_async = function(_, method, cb)
          local function uri(p) return vim.uri_from_fname(p) end

          if method == Methods.textDocument_references then
            cb({
              mock = {
                { uri = uri(_G.USAGE_PATH), range = { start = { line = 2, character = 10 }, ["end"] = { line = 2, character = 17 } } },
                { uri = uri(_G.USAGE_PATH), range = { start = { line = 3, character = 7  }, ["end"] = { line = 3, character = 14 } } },
              },
            })
          elseif method == Methods.textDocument_definition then
            cb({
              mock = {
                { uri = uri(_G.MODULE_PATH), range = { start = { line = 3, character = 0 }, ["end"] = { line = 5, character = 3 } } },
              },
            })
          elseif method == Methods.textDocument_hover then
            cb({ mock = { contents = "My function docs" } })
          else
            cb({ mock = {} })
          end
        end
      ]])
    end,
    post_case = function()
      child.lua([[
        -- Cleanup
        pcall(vim.cmd, 'cd -')
        pcall(vim.loop.fs_unlink, _G.MODULE_PATH)
        pcall(vim.loop.fs_unlink, _G.USAGE_PATH)
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["list_code_usages integration"] = function()
  -- Execute tool
  child.lua([[
    local args = vim.json.encode({
      symbol_name = "my_func",
      file_paths = { _G.MODULE_PATH },
    })

    local tool = {
      {
        ["function"] = {
          name = "list_code_usages",
          arguments = args,
        },
      },
    }

    tools:execute(chat, tool)

    -- Wait for async schedules to complete and message to be appended
    vim.wait(2000, function()
      local msg = chat.messages[#chat.messages]
      return type(msg) == "table" and type(msg.content) == "string" and msg.content:find("Searched for symbol `my_func`", 1, true) ~= nil
    end)
  ]])

  local output = child.lua_get("chat.messages[#chat.messages].content")

  -- Basic success banner
  h.expect_contains("Searched for symbol `my_func`", output)

  -- Has sections for definition and references
  h.expect_contains("\ndefinition:\n", output)
  h.expect_contains("\nreferences:\n", output)

  -- Documentation included
  h.expect_contains("My function docs", output)

  -- Includes lua fenced code blocks
  h.expect_contains("```lua", output)

  -- Filenames are relative
  h.expect_contains("src/module.lua", output)
  h.expect_contains("src/usage.lua", output)
end

return T
