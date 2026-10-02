local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
    end,
    post_once = child.stop,
  },
})

---@param content string
---@param opts { old_string: string, new_string: string, replace_all?: boolean }
---@return { content?: string, error?: string }
local function apply(content, opts)
  return child.lua(
    [[
    return require("codecompanion.interactions.chat.tools.builtin.edit_file.replace").apply(...)
  ]],
    { content, opts }
  )
end

T["Replace"] = new_set()

T["Replace"]["replaces a unique match"] = function()
  local result = apply("local x = 1\nlocal y = 2\n", { old_string = "local y = 2", new_string = "local y = 3" })
  h.eq("local x = 1\nlocal y = 3\n", result.content)
end

T["Replace"]["treats old_string as plain text, not a pattern"] = function()
  local result = apply("call(a.b)\ncall(aXb)\n", { old_string = "call(a.b)", new_string = "done" })
  h.eq("done\ncall(aXb)\n", result.content)
end

T["Replace"]["writes % in new_string literally"] = function()
  local result = apply("x = 1\n", { old_string = "x = 1", new_string = 'x = ("%1 %%"):format()' })
  h.eq('x = ("%1 %%"):format()\n', result.content)
end

T["Replace"]["refuses an old_string that matches more than once"] = function()
  local result = apply("foo\nbar\nfoo\n", { old_string = "foo", new_string = "baz" })
  h.eq(nil, result.content)
  h.expect_contains("matches 2 places", result.error)
end

T["Replace"]["replaces every match with replace_all"] = function()
  local result = apply("foo\nbar\nfoo\n", { old_string = "foo", new_string = "baz", replace_all = true })
  h.eq("baz\nbar\nbaz\n", result.content)
end

T["Replace"]["does not match when the indentation differs"] = function()
  local result = apply("\tif x:\n\t\treturn 1\n", { old_string = "    return 1", new_string = "    return 2" })
  h.eq(nil, result.content)
  h.expect_contains("was not found", result.error)
end

T["Replace"]["removes the newline when deleting a WHOLE line"] = function()
  local result = apply("a\nb\nc\n", { old_string = "b", new_string = "" })
  h.eq("a\nc\n", result.content)
end

T["Replace"]["removes the newline from every line deleted with replace_all"] = function()
  local result = apply("keep\ndrop\nkeep\ndrop\n", { old_string = "drop", new_string = "", replace_all = true })
  h.eq("keep\nkeep\n", result.content)
end

T["Replace"]["keeps the newline when deleting PART of a line"] = function()
  local result = apply("a = 1 -- note\nb = 2\n", { old_string = " -- note", new_string = "" })
  h.eq("a = 1\nb = 2\n", result.content)
end

T["Replace"]["matches straight quotes against curly quotes and keeps the file's style"] = function()
  local result = apply(
    "He said “hello” and it’s fine\n",
    { old_string = [[He said "hello" and it's fine]], new_string = [[He said "goodbye" and it's fine]] }
  )
  h.eq("He said “goodbye” and it’s fine\n", result.content)
end

T["Replace"]["matches curly quotes AFTER earlier curly quotes in the file"] = function()
  local result = apply(
    "Title: “Notes”\nShe said “hi” today\n",
    { old_string = [[She said "hi" today]], new_string = [[She said "hello" today]] }
  )
  h.eq("Title: “Notes”\nShe said “hello” today\n", result.content)
end

T["Replace"]["only curls the quote type found in the match"] = function()
  local result =
    apply("Say “hi” now\n", { old_string = [[Say "hi" now]], new_string = [[Say "hi" now, don't wait]] })
  h.eq("Say “hi” now, don't wait\n", result.content)
end

T["Replace"]["matches a CRLF old_string against LF content"] = function()
  local result = apply("a\nb\n", { old_string = "a\r\nb", new_string = "a\r\nc" })
  h.eq("a\nc\n", result.content)
end

T["Replace"]["fills an empty file when old_string is empty"] = function()
  local result = apply("", { old_string = "", new_string = "hello\n" })
  h.eq("hello\n", result.content)
end

T["Replace"]["refuses an empty old_string in a non-empty file"] = function()
  local result = apply("hello\n", { old_string = "", new_string = "world" })
  h.eq(nil, result.content)
  h.expect_contains("`old_string` is empty", result.error)
end

return T
