local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.TEST_CWD = vim.fn.tempname()
        _G.TEST_DIR = "tests/stubs/read_file"
        _G.TEST_DIR_ABSOLUTE = vim.fs.joinpath(_G.TEST_CWD, _G.TEST_DIR)
        _G.TEST_TMPFILE = "cc_readfile_test.txt"
        _G.TEST_TMPFILE_ABSOLUTE = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, _G.TEST_TMPFILE)

        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE, "p")
        assert(vim.fn.writefile({ "alpha", "beta", "gamma", "delta" }, _G.TEST_TMPFILE_ABSOLUTE) == 0)

        h = require("tests.helpers")
        chat, tools = h.setup_chat_buffer()
        vim.uv.chdir(_G.TEST_CWD)

        function _G.execute_read_file(arguments)
          arguments = vim.tbl_extend("force", { filepath = _G.TEST_TMPFILE_ABSOLUTE }, arguments or {})
          local message_count = #chat.messages
          local tool = {
            {
              ["function"] = {
                name = "read_file",
                arguments = vim.json.encode(arguments),
              },
            },
          }

          tools:execute(chat, tool)
          assert(vim.wait(1000, function()
            return #chat.messages > message_count
          end), "read_file did not produce output")

          return chat.messages[#chat.messages].content
        end

        function _G.write_test_file(lines)
          assert(vim.fn.writefile(lines, _G.TEST_TMPFILE_ABSOLUTE) == 0)
        end

        function _G.chat_buffer_text()
          return table.concat(vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), "\n")
        end
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.fn.delete, _G.TEST_CWD, "rf")
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

local function execute_read_file(arguments)
  return child.lua_get([[_G.execute_read_file(...)]], { arguments or {} })
end

local function write_test_file(lines)
  child.lua([[_G.write_test_file(...)]], { lines })
end

local function expect_lines(output, included, excluded)
  for _, line in ipairs(included or {}) do
    h.expect_contains(line, output)
  end
  for _, line in ipairs(excluded or {}) do
    h.expect_not_contains(line, output)
  end
end

local function expect_error(output, ...)
  h.expect_contains("Error reading", output)
  for _, term in ipairs({ ... }) do
    h.expect_contains(term, output)
  end
end

T["reads an explicit inclusive range"] = function()
  local output = execute_read_file({ start_line = 1, end_line = 2 })

  expect_lines(output, { "beta", "gamma" }, { "alpha", "delta" })
end

T["reads the whole file when bounds are omitted"] = function()
  local output = execute_read_file()

  expect_lines(output, { "alpha", "beta", "gamma", "delta" })
  h.expect_contains("from lines 0 - 3", output)
end

T["reads an empty file as a single empty line"] = function()
  write_test_file({})
  local output = execute_read_file()

  h.expect_contains("from lines 0 - 0", output)
  h.eq(nil, output:find("Error reading", 1, true))
end

T["reads a single line file"] = function()
  write_test_file({ "solo" })
  local output = execute_read_file()

  expect_lines(output, { "solo" })
  h.expect_contains("from lines 0 - 0", output)
end

T["reads a path relative to the current working directory"] = function()
  local output = execute_read_file({ filepath = "tests/stubs/read_file/cc_readfile_test.txt" })

  expect_lines(output, { "alpha", "beta", "gamma", "delta" })
end

T["reads from start_line to the end of the file"] = function()
  local output = execute_read_file({ start_line = 1 })

  expect_lines(output, { "beta", "gamma", "delta" }, { "alpha" })
end

T["reads from the start of the file through end_line"] = function()
  local output = execute_read_file({ end_line = 1 })

  expect_lines(output, { "alpha", "beta" }, { "gamma", "delta" })
end

T["treats empty bounds as omitted"] = function()
  local output = execute_read_file({ start_line = "", end_line = "" })

  expect_lines(output, { "alpha", "beta", "gamma", "delta" })
end

T["treats JSON null bounds as omitted"] = function()
  local output = execute_read_file({ start_line = vim.NIL, end_line = vim.NIL })

  expect_lines(output, { "alpha", "beta", "gamma", "delta" })
end

T["normalizes a negative start_line to the start of the file"] = function()
  local output = execute_read_file({ start_line = -37, end_line = 1 })

  expect_lines(output, { "alpha", "beta" }, { "gamma", "delta" })
end

T["normalizes a negative end_line to the end of the file"] = function()
  local output = execute_read_file({ start_line = 2, end_line = -91 })

  expect_lines(output, { "gamma", "delta" }, { "alpha", "beta" })
  h.expect_contains("from lines 2 - 3", output)
end

T["reads only the first line for range zero to zero"] = function()
  local output = execute_read_file({ start_line = 0, end_line = 0 })

  expect_lines(output, { "alpha" }, { "beta", "gamma", "delta" })
end

T["clamps an oversized end_line to the end of the file"] = function()
  local output = execute_read_file({ start_line = 2, end_line = 100 })

  expect_lines(output, { "gamma", "delta" }, { "alpha", "beta" })
  h.expect_contains("from lines 2 - 3", output)
end

T["shows the resolved range in the chat buffer"] = function()
  execute_read_file({ end_line = 100 })

  h.expect_contains("cc_readfile_test.txt` (0 - 3)", child.lua_get([[_G.chat_buffer_text()]]))
end

T["rejects a malformed start_line"] = function()
  local output = execute_read_file({ start_line = "later", end_line = 2 })

  expect_error(output, "start_line")
end

T["rejects a malformed end_line"] = function()
  local output = execute_read_file({ start_line = 1, end_line = "later" })

  expect_error(output, "end_line")
end

T["rejects a reversed finite range"] = function()
  local output = execute_read_file({ start_line = 2, end_line = 1 })

  expect_error(output, "start_line", "end_line")
end

T["rejects a start_line beyond the end of the file"] = function()
  local output = execute_read_file({ start_line = 4 })

  expect_error(output, "start_line")
end

return T
