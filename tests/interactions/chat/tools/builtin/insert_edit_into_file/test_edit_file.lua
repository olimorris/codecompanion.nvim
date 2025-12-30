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
        _G.TEST_DIR = 'tests/stubs/read_file'
        _G.TEST_DIR_ABSOLUTE = vim.fs.joinpath(_G.TEST_CWD, _G.TEST_DIR)

        -- Create test directory structure
        vim.fn.mkdir(_G.TEST_DIR_ABSOLUTE, 'p')

        _G.TEST_TMPFILE = vim.fs.joinpath(_G.TEST_DIR_ABSOLUTE, "insert_edit_into_file_test.txt")

        h = require('tests.helpers')

        -- Setup chat buffer (insert_edit_into_file is already enabled in test config)
        chat, tools = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[
        pcall(vim.loop.fs_unlink, _G.TEST_TMPFILE)
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

-- ============================================================================
-- Core Functionality Tests
-- ============================================================================

T["Core Functionality"] = new_set()

T["Core Functionality"]["performs basic single edit"] = function()
  child.lua([[
    local initial = "function getName() {\n  return 'John';\n}"
    vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "function getName() {\\n  return \'John\';\\n}", "newText": "function getFullName() {\\n  return \'John Doe\';\\n}"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output, { "function getFullName() {", "  return 'John Doe';", "}" })
end

T["Core Functionality"]["handles multiple sequential edits"] = function()
  child.lua([[
    local initial = "function getName() {\n  return 'John';\n}\n\nfunction getAge() {\n  return 25;\n}"
    vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "function getName() {\\n  return \'John\';\\n}", "newText": "function getFullName() {\\n  return \'John Doe\';\\n}"}, {"oldText": "function getAge() {\\n  return 25;\\n}", "newText": "function getAge() {\\n  return 30;\\n}"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(
    output,
    { "function getFullName() {", "  return 'John Doe';", "}", "", "function getAge() {", "  return 30;", "}" }
  )
end

T["Core Functionality"]["supports dry run mode"] = function()
  child.lua([[
    local initial = "const x = 1;"
    vim.fn.writefile({ initial }, _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "dryRun": true, "edits": [{"oldText": "const x = 1;", "newText": "const x = 2;"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output, { "const x = 1;" }, "Dry run should not modify file")
end

-- ============================================================================
-- Edit Types Tests
-- ============================================================================

T["Edit Types"] = new_set()

T["Edit Types"]["handles substring replaceAll edits"] = function()
  child.lua([[
    local initial = "var x = 1;\nvar y = 2;\nfunction test() {\n  var z = 3;\n}\nvar a = 4;"
    vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "var", "newText": "let", "replaceAll": true}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output, { "let x = 1;", "let y = 2;", "function test() {", "  let z = 3;", "}", "let a = 4;" })
end

T["Edit Types"]["handles mixed block and substring edits"] = function()
  child.lua([[
    local initial = "// TODO: fix\nfunction test() {\n  return 1;\n}\n// TODO: refactor"
    vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "TODO:", "newText": "DONE:", "replaceAll": true}, {"oldText": "function test() {\\n  return 1;\\n}", "newText": "function test() {\\n  return 10;\\n}"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output, { "// DONE: fix", "function test() {", "  return 10;", "}", "// DONE: refactor" })
end

-- ============================================================================
-- Matching & Strategies Tests
-- ============================================================================

T["Matching & Strategies"] = new_set()

T["Matching & Strategies"]["normalizes whitespace when matching"] = function()
  child.lua([[
    -- File has extra whitespace, edit has normalized whitespace
    local initial = "const x  =   { a:1,   b:2 };"
    vim.fn.writefile({ initial }, _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "const x = { a:1, b:2 };", "newText": "const x = { a:1, b:2, c:3 };"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output[1], "const x = { a:1, b:2, c:3 };")
end

T["Matching & Strategies"]["handles special characters and unicode"] = function()
  child.lua([[
    local initial = "const message = 'こんにちは世界';"
    vim.fn.writefile({ initial }, _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "こんにちは世界", "newText": "こんばんは世界", "replaceAll": true}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("table.concat(vim.fn.readfile(_G.TEST_TMPFILE), '\\n')")
  h.expect_contains("こんばんは世界", output)
end

T["Matching & Strategies"]["uses appropriate strategy for context"] = function()
  child.lua([[
    -- Test that block_anchor strategy works with method context
    local initial = "class Calculator {\n  add(a, b) {\n    return a + b;\n  }\n  \n  multiply(x, y) {\n    return x * y;\n  }\n}"
    vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "  add(a, b) {\\n    return a + b;\\n  }", "newText": "  add(a, b) {\\n    const result = a + b;\\n    return result;\\n  }"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("table.concat(vim.fn.readfile(_G.TEST_TMPFILE), '\\n')")
  h.expect_contains("const result = a + b;", output)
end

-- ============================================================================
-- Error Handling Tests
-- ============================================================================

T["Error Handling"] = new_set()

T["Error Handling"]["reports file not found"] = function()
  child.lua([[
    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = '{"filepath": "/nonexistent/file.txt", "edits": [{"oldText": "foo", "newText": "bar"}]}'
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)

    _G.last_message = chat.messages[#chat.messages].content
  ]])

  local output = child.lua_get("_G.last_message")
  h.expect_contains("File does not exist", output)
end

T["Error Handling"]["reports invalid JSON in edits"] = function()
  child.lua([[
    local initial = "test"
    vim.fn.writefile({ initial }, _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": "not valid json"}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)

    _G.last_message = chat.messages[#chat.messages].content
  ]])

  local output = child.lua_get("_G.last_message")
  h.expect_contains("parse", output)
end

T["Error Handling"]["reports when text not found"] = function()
  child.lua([[
    local initial = "const x = 1;"
    vim.fn.writefile({ initial }, _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "const y = 2;", "newText": "const y = 3;"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)

    _G.last_message = chat.messages[#chat.messages].content
  ]])

  local output = child.lua_get("_G.last_message")
  h.expect_contains("No confident matches found", output)
end

-- ============================================================================
-- Edge Cases Tests
-- ============================================================================

T["Edge Cases"] = new_set()

T["Edge Cases"]["handles boundary conditions"] = function()
  -- Test empty file
  child.lua([[
    vim.fn.writefile({}, _G.TEST_TMPFILE)
    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "", "newText": "// New file"}]}', _G.TEST_TMPFILE)
      },
    }}
    tools:execute(chat, tool)
    vim.wait(10)
  ]])
  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output, { "// New file" })

  -- Test single line
  child.lua([[
    vim.fn.writefile({ "Hello World" }, _G.TEST_TMPFILE)
    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "Hello World", "newText": "Hello Universe"}]}', _G.TEST_TMPFILE)
      },
    }}
    tools:execute(chat, tool)
    vim.wait(10)
  ]])
  output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output, { "Hello Universe" })

  -- Test beginning of file
  child.lua([[
    vim.fn.writefile(vim.split("#!/usr/bin/env python3\nprint('hello')", "\n"), _G.TEST_TMPFILE)
    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "#!/usr/bin/env python3", "newText": "#!/usr/bin/env python3\\n# -*- coding: utf-8 -*-"}]}', _G.TEST_TMPFILE)
      },
    }}
    tools:execute(chat, tool)
    vim.wait(10)
  ]])
  output = child.lua_get("table.concat(vim.fn.readfile(_G.TEST_TMPFILE), '\\n')")
  h.expect_contains("coding: utf-8", output)

  -- Test end of file
  child.lua([[
    vim.fn.writefile(vim.split("function main() {\n  console.log('test');\n}", "\n"), _G.TEST_TMPFILE)
    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "}", "newText": "}\\n\\nmain();"}]}', _G.TEST_TMPFILE)
      },
    }}
    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  output = child.lua_get("table.concat(vim.fn.readfile(_G.TEST_TMPFILE), '\\n')")
  h.expect_contains("main();", output)
end

T["Edge Cases"]["handles sequential edits creating ambiguity"] = function()
  child.lua([[
    -- First edit creates a pattern that could match the second edit
    local initial = "function test() {\n  return 1;\n}\nfunction test() {\n  return 2;\n}"
    vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "function test() {\\n  return 1;\\n}", "newText": "function test() {\\n  return 10;\\n}"}, {"oldText": "function test() {\\n  return 2;\\n}", "newText": "function test() {\\n  return 20;\\n}"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("vim.fn.readfile(_G.TEST_TMPFILE)")
  h.eq(output, { "function test() {", "  return 10;", "}", "function test() {", "  return 20;", "}" })
end

-- ============================================================================
-- Integration Tests
-- ============================================================================

T["Integration"] = new_set()

T["Integration"]["handles complex multi-edit transformation"] = function()
  child.lua([[
    -- Real-world scenario: refactoring a function with error handling
    local initial = "async function fetchUserData(userId) {\n  const response = await fetch(`/api/users/${userId}`);\n  return response.json();\n}"
    vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "async function fetchUserData(userId) {\\n  const response = await fetch(`/api/users/${userId}`);\\n  return response.json();\\n}", "newText": "async function fetchUserData(userId) {\\n  try {\\n    const response = await fetch(`/api/users/${userId}`);\\n    if (!response.ok) throw new Error(`HTTP ${response.status}`);\\n    return response.json();\\n  } catch (error) {\\n    console.error(\'Failed to fetch user:\', error);\\n    throw error;\\n  }\\n}"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("table.concat(vim.fn.readfile(_G.TEST_TMPFILE), '\\n')")
  h.expect_contains("try {", output)
  h.expect_contains("console.error", output)
end

T["Integration"]["handles sequential variable renaming"] = function()
  child.lua([[
    -- Multiple sequential edits improving code quality
    local initial = "function calc(a, b) {\n  let x = a + b;\n  let y = x * 2;\n  return y;\n}"
    vim.fn.writefile(vim.split(initial, "\n"), _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "function calc(a, b) {", "newText": "function calculateDoubleSum(firstNumber, secondNumber) {"}, {"oldText": "  let x = a + b;", "newText": "  const sum = firstNumber + secondNumber;"}, {"oldText": "  let y = x * 2;", "newText": "  const doubleSum = sum * 2;"}, {"oldText": "  return y;", "newText": "  return doubleSum;"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(10)
  ]])

  local output = child.lua_get("table.concat(vim.fn.readfile(_G.TEST_TMPFILE), '\\n')")
  h.expect_contains("calculateDoubleSum", output)
  h.expect_contains("firstNumber", output)
end

T["Integration"]["verifies diff workflow"] = function()
  child.lua([[
    vim.fn.writefile(vim.split("function getName() {\n  return 'John';\n}", "\n"), _G.TEST_TMPFILE)

    local tool = {{
      ["function"] = {
        name = "insert_edit_into_file",
        arguments = string.format('{"filepath": "%s", "edits": [{"oldText": "function getName() {\\n  return \'John\';\\n}", "newText": "function getFullName() {\\n  return \'John Doe\';\\n}"}]}', _G.TEST_TMPFILE)
      },
    }}

    tools:execute(chat, tool)
    vim.wait(100)

    -- Check that file was written
    local file_content = vim.fn.readfile(_G.TEST_TMPFILE)
    _G.file_has_new_content = vim.tbl_contains(file_content, "function getFullName() {")
  ]])

  local has_new_content = child.lua_get("_G.file_has_new_content")
  h.eq(has_new_content, true)
end

return T
