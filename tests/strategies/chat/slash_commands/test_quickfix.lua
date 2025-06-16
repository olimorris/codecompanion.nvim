local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
local new_set = MiniTest.new_set

T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })

      child.lua([[
        h = require('tests.helpers')
        _G.chat, _ = h.setup_chat_buffer()

        _G.qflist = require("codecompanion.strategies.chat.slash_commands.quickfix").new({
          Chat = chat,
          config = {
            opts = {
              contains_code = true,
            },
          },
          context = {},
          opts = {},
        })

        -- Helper function to create actual files and buffers for testing
        function _G.create_test_files()
          -- Create actual files
          vim.fn.writefile({"-- test lua file", "local x = 1"}, "test_file.lua")
          vim.fn.writefile({"// test js file", "var y = 2;"}, "another_file.js")
          vim.fn.writefile({"test content"}, "pure_file.txt")
        end

        function _G.cleanup_test_files()
          vim.fn.delete("test_file.lua")
          vim.fn.delete("another_file.js") 
          vim.fn.delete("pure_file.txt")
        end

        -- Helper function to setup quickfix list with file entries
        function _G.setup_qflist_with_files()
          _G.create_test_files()
          
          -- Load files into buffers first
          local buf1 = vim.fn.bufadd("test_file.lua")
          local buf2 = vim.fn.bufadd("another_file.js")
          
          vim.fn.setqflist({
            { bufnr = buf1, lnum = 1, text = "test_file.lua" },
            { bufnr = buf2, lnum = 1, text = "another_file.js" },
          })
        end

        function _G.setup_qflist_with_diagnostics()
          _G.create_test_files()
          
          local buf1 = vim.fn.bufadd("test_file.lua")
          local buf2 = vim.fn.bufadd("another_file.js")
          
          vim.fn.setqflist({
            { bufnr = buf1, lnum = 10, text = "undefined variable 'foo'" },
            { bufnr = buf1, lnum = 15, text = "unused variable 'bar'" },
            { bufnr = buf2, lnum = 25, text = "missing semicolon" },
          })
        end

        function _G.setup_qflist_mixed()
          _G.create_test_files()
          
          local buf1 = vim.fn.bufadd("test_file.lua")
          local buf3 = vim.fn.bufadd("pure_file.txt")
          
          vim.fn.setqflist({
            { bufnr = buf1, lnum = 10, text = "undefined variable 'foo'" },
            { bufnr = buf1, lnum = 12, text = "unused variable 'bar'" },
            { bufnr = buf3, lnum = 1, text = "pure_file.txt" },
          })
        end

        -- Helper function to get quickfix entries count
        function _G.get_qflist_count()
          return #vim.fn.getqflist()
        end

        -- Helper to test file detection 
        function _G.test_file_detection()
          local qflist = vim.fn.getqflist()
          local file_entries = 0
          
          for _, item in ipairs(qflist) do
            local filename = vim.fn.bufname(item.bufnr)
            local text = item.text or ""
            
            if filename ~= "" then
              local escaped_filename = vim.pesc(filename)
              local is_file_entry = text:match(escaped_filename .. "$") ~= nil
              
              if is_file_entry then
                file_entries = file_entries + 1
              end
            end
          end
          
          return file_entries
        end

        -- Helper to test diagnostic detection
        function _G.test_diagnostic_detection()
          local qflist = vim.fn.getqflist()
          local diagnostic_entries = 0
          
          for _, item in ipairs(qflist) do
            local filename = vim.fn.bufname(item.bufnr)
            local text = item.text or ""
            
            if filename ~= "" then
              local escaped_filename = vim.pesc(filename)
              local is_file_entry = text:match(escaped_filename .. "$") ~= nil
              
              if not is_file_entry then
                diagnostic_entries = diagnostic_entries + 1
              end
            end
          end
          
          return diagnostic_entries
        end

        -- Helper to test file grouping
        function _G.test_file_grouping()
          local qflist = vim.fn.getqflist()
          local files = {}
          
          for _, item in ipairs(qflist) do
            local filename = vim.fn.bufname(item.bufnr)
            local text = item.text or ""
            
            if filename ~= "" then
              if not files[filename] then
                files[filename] = { diagnostics = 0, has_diagnostics = false }
              end
              
              local escaped_filename = vim.pesc(filename)
              local is_file_entry = text:match(escaped_filename .. "$") ~= nil
              
              if not is_file_entry then
                files[filename].diagnostics = files[filename].diagnostics + 1
                files[filename].has_diagnostics = true
              end
            end
          end
          
          return files
        end
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
        vim.fn.setqflist({})
        _G.cleanup_test_files()
      ]])
    end,
    post_once = child.stop,
  },
})

T["Quickfix"] = new_set()

T["Quickfix"]["handles empty quickfix list"] = function()
  child.lua([[vim.fn.setqflist({})]])
  local count = child.lua_get("_G.get_qflist_count()")
  h.eq(0, count)
end

T["Quickfix"]["detects file entries correctly"] = function()
  child.lua([[_G.setup_qflist_with_files()]])
  local file_entries = child.lua_get("_G.test_file_detection()")
  local total_entries = child.lua_get("_G.get_qflist_count()")
  h.eq(2, total_entries)
  h.eq(2, file_entries)
end

T["Quickfix"]["detects diagnostic entries correctly"] = function()
  child.lua([[_G.setup_qflist_with_diagnostics()]])
  local diagnostic_entries = child.lua_get("_G.test_diagnostic_detection()")
  local total_entries = child.lua_get("_G.get_qflist_count()")
  h.eq(3, total_entries)
  h.eq(3, diagnostic_entries)
end

T["Quickfix"]["groups diagnostics by file"] = function()
  child.lua([[_G.setup_qflist_mixed()]])
  local file_groups = child.lua_get("_G.test_file_grouping()")
  h.eq(2, vim.tbl_count(file_groups))
  h.eq(true, file_groups["test_file.lua"].has_diagnostics)
  h.eq(2, file_groups["test_file.lua"].diagnostics)
  h.eq(false, file_groups["pure_file.txt"].has_diagnostics)
  h.eq(0, file_groups["pure_file.txt"].diagnostics)
end

return T
