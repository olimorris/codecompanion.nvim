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
  h.expect_not_contains("Error reading", output)
end

T["treats empty and null bounds as omitted"] = function()
  local output = execute_read_file({ start_line = "", end_line = vim.NIL })

  expect_lines(output, { "alpha", "beta", "gamma", "delta" })
end

T["treats negative bounds as omitted"] = function()
  expect_lines(execute_read_file({ start_line = -37, end_line = 1 }), { "alpha", "beta" }, { "gamma", "delta" })
  expect_lines(execute_read_file({ start_line = 2, end_line = -91 }), { "gamma", "delta" }, { "alpha", "beta" })
end

T["clamps an oversized end_line to the end of the file"] = function()
  local output = execute_read_file({ start_line = 2, end_line = 100 })

  expect_lines(output, { "gamma", "delta" }, { "alpha", "beta" })
  h.expect_contains("from lines 2 - 3", output)
end

T["rejects a malformed bound"] = function()
  expect_error(execute_read_file({ start_line = "later", end_line = 2 }), "start_line")
  expect_error(execute_read_file({ start_line = 1, end_line = "later" }), "end_line")
end

T["rejects a reversed finite range"] = function()
  local output = execute_read_file({ start_line = 2, end_line = 1 })

  expect_error(output, "start_line", "end_line")
end

T["rejects a start_line beyond the end of the file"] = function()
  local output = execute_read_file({ start_line = 4 })

  expect_error(output, "start_line")
end

---@param opts? { mode?: string, protect?: boolean, cached?: boolean, require_approval_before?: boolean, always_allow?: table, always_confirm?: table, filepath?: string }
local function queue_permission_read(opts)
  opts = opts or {}
  child.lua(
    [[
    local options = ...
    local config = require("codecompanion.config")
    config.interactions.chat.tools.read_file.opts = vim.tbl_extend("force",
      config.interactions.chat.tools.read_file.opts, {
        protect = options.protect == true,
        require_approval_before = options.require_approval_before ~= false,
        always_allow = options.always_allow or {},
        always_confirm = options.always_confirm or {},
      })
    tools.tools_config.read_file.opts = config.interactions.chat.tools.read_file.opts
    local approvals = require("codecompanion.interactions.chat.tools.approvals")
    approvals:set_mode(tools.bufnr, { mode = options.mode or "auto" })
    if options.cached then
      approvals:always(tools.bufnr, { tool_name = "read_file" })
    end
    _G.permission_prompts = {}
    require("codecompanion.interactions.chat.helpers.approval_prompt").request = function(_, request)
      table.insert(_G.permission_prompts, request)
    end
    _G.permission_message_count = #chat.messages
    _G.permission_call = {
      { ["function"] = {
        name = "read_file",
        arguments = vim.json.encode({ filepath = options.filepath or _G.TEST_TMPFILE_ABSOLUTE }),
      } },
    }
    tools:execute(chat, _G.permission_call)
    vim.wait(1000, function()
      return #_G.permission_prompts > 0 or #chat.messages > _G.permission_message_count
    end)
  ]],
    { opts }
  )
end

local function expect_permission_read()
  h.eq(0, child.lua_get("#_G.permission_prompts"))
  h.expect_contains("alpha", child.lua_get("chat.messages[#chat.messages].content"))
end

T["always_allow bypasses protection for a normalized relative path"] = function()
  queue_permission_read({
    protect = true,
    filepath = "tests/stubs/read_file/../read_file/cc_readfile_test.txt",
    always_allow = { { pattern = [[^/.*/tests/stubs/read_file/cc_readfile_test\.txt$]] } },
  })

  expect_permission_read()
end

T["always_allow DOES NOT bypass protection for an unmatched path"] = function()
  queue_permission_read({ protect = true, always_allow = { { pattern = "/other/" } } })

  h.eq(1, child.lua_get("#_G.permission_prompts"))
  h.eq(true, child.lua_get("#chat.messages == _G.permission_message_count"))
end

T["always_confirm overrides cached approval and a matching allowance"] = function()
  queue_permission_read({
    cached = true,
    require_approval_before = false,
    always_allow = { { pattern = "/read_file/" } },
    always_confirm = { { pattern = "/read_file/" } },
  })

  h.eq(1, child.lua_get("#_G.permission_prompts"))
  h.eq(true, child.lua_get("#chat.messages == _G.permission_message_count"))
  h.eq(3, child.lua_get("#_G.permission_prompts[1].choices"))
  child.lua([[
    _G.permission_prompts[1].choices[1].callback()
    assert(vim.wait(1000, function()
      return #chat.messages > _G.permission_message_count
    end))
    tools:execute(chat, _G.permission_call)
  ]])
  h.eq(2, child.lua_get("#_G.permission_prompts"))
end

T["always_confirm DOES NOT prompt for an unmatched path"] = function()
  queue_permission_read({ always_confirm = { { pattern = "/other/" } } })

  expect_permission_read()
end

T["invalid permission patterns require confirmation before reading"] = function()
  queue_permission_read({ always_allow = { { pattern = "(" } } })

  h.eq(1, child.lua_get("#_G.permission_prompts"))
  h.eq(true, child.lua_get("#chat.messages == _G.permission_message_count"))
end

T["always_allow DOES NOT bypass approval in ask mode"] = function()
  queue_permission_read({ mode = "ask", always_allow = { { pattern = "/read_file/" } } })

  h.eq(1, child.lua_get("#_G.permission_prompts"))
end

T["always_confirm DOES NOT override cached approval in ask mode"] = function()
  queue_permission_read({ mode = "ask", cached = true, always_confirm = { { pattern = "/read_file/" } } })

  expect_permission_read()
end

T["always_confirm DOES NOT override yolo mode"] = function()
  queue_permission_read({ mode = "yolo", always_confirm = { { pattern = "/read_file/" } } })

  expect_permission_read()
end

return T
