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

local function expect_lines(output, included, excluded)
  for _, line in ipairs(included or {}) do
    h.expect_contains(line, output)
  end
  for _, line in ipairs(excluded or {}) do
    h.eq(nil, output:find(line, 1, true))
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

T["rejects a malformed start_line"] = function()
  local output = execute_read_file({ start_line = "later", end_line = 2 })

  h.expect_contains("Error reading", output)
  h.expect_contains("start_line", output)
end

T["rejects a malformed end_line"] = function()
  local output = execute_read_file({ start_line = 1, end_line = "later" })

  h.expect_contains("Error reading", output)
  h.expect_contains("end_line", output)
end

T["rejects a fractional bound"] = function()
  local output = execute_read_file({ start_line = 0.5, end_line = 2 })

  h.expect_contains("Error reading", output)
  h.expect_contains("start_line", output)
end

T["rejects a reversed finite range"] = function()
  local output = execute_read_file({ start_line = 2, end_line = 1 })

  h.expect_contains("Error reading", output)
  h.expect_contains("start_line", output)
  h.expect_contains("end_line", output)
end

T["rejects a start_line beyond the end of the file"] = function()
  local output = execute_read_file({ start_line = 4 })

  h.expect_contains("Error reading", output)
  h.expect_contains("start_line", output)
end

T["reports files that do not exist"] = function()
  local output = execute_read_file({ filepath = "/does/not/exist.txt" })

  h.expect_contains("Error reading", output)
end

T["advertises only the canonical arguments"] = function()
  local schema = child.lua_get([[
    (function()
      local parameters = require("codecompanion.interactions.chat.tools.builtin.read_file").schema["function"].parameters
      local property_names = vim.tbl_keys(parameters.properties)
      table.sort(property_names)

      return {
        property_names = property_names,
        required = parameters.required,
        filepath_type = parameters.properties.filepath.type,
        start_line_type = parameters.properties.start_line.type,
        end_line_type = parameters.properties.end_line.type,
      }
    end)()
  ]])

  h.eq({
    property_names = { "end_line", "filepath", "start_line" },
    required = { "filepath" },
    filepath_type = "string",
    start_line_type = "integer",
    end_line_type = "integer",
  }, schema)
end

T["accepts the legacy range argument names"] = function()
  local output = execute_read_file({
    start_line_number_base_zero = 1,
    end_line_number_base_zero = 2,
  })

  expect_lines(output, { "beta", "gamma" }, { "alpha", "delta" })
end

T["prefers canonical range arguments over legacy aliases"] = function()
  local output = execute_read_file({
    start_line = 0,
    end_line = 0,
    start_line_number_base_zero = 1,
    end_line_number_base_zero = 2,
  })

  expect_lines(output, { "alpha" }, { "beta", "gamma", "delta" })
end

return T
