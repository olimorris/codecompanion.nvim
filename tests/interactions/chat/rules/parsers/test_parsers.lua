local new_set = MiniTest.new_set
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "scripts/minimal_init.lua" })
    end,
    post_once = child.stop,
  },
})

T["parsers.resolve()"] = new_set()

T["parsers.resolve()"]["handles function parsers"] = function()
  child.lua([[
    package.loaded['codecompanion.config'] = {
      rules = {
        parsers = {
          fn_par = function()
            return { content = function(p) return "F:" .. (p.content or "") end }
          end
        }
      }
    }
  ]])

  local f_res = child.lua([[
    local parsers = require("codecompanion.interactions.chat.rules.parsers")
    local p = parsers.resolve("fn_par")
    return p.content({ content = "b\n" })
  ]])
  h.eq(f_res, "F:b\n")
end

T["parsers.resolve()"]["supports builtin module name and file-based parser"] = function()
  -- Mock the built-in parser module
  child.lua([[
    package.loaded["codecompanion.interactions.chat.rules.parsers.builtinmod"] = {
      content = function(p) return "BUILTIN:" .. (p.content or "") end
    }
    package.loaded['codecompanion.config'] = {
      rules = { parsers = { builtin_parser = "builtinmod" } }
    }
  ]])

  local built = child.lua([[
    local parsers = require("codecompanion.interactions.chat.rules.parsers")
    local p = parsers.resolve("builtin_parser")
    return p.content({ content = "I am a builtin parser\n" })
  ]])
  h.eq(built, "BUILTIN:I am a builtin parser\n")

  -- File-based parser: create temp file that returns a parser table
  local tmp = child.lua("return vim.fn.tempname()")
  child.fn.writefile({ 'return { content = function(p) return "FILE:" .. (p.content or "") end }' }, tmp)

  child.lua(string.format(
    [[
    package.loaded['codecompanion.config'] = {
      rules = { parsers = { file_parser = %q } }
    }
  ]],
    tmp
  ))

  child.lua([[ package.loaded['codecompanion.interactions.chat.rules.parsers'] = nil ]])

  local file_res = child.lua([[
    local parsers = require("codecompanion.interactions.chat.rules.parsers")
    local p = parsers.resolve("file_parser")
    return p.content({ content = "I am a file-based parser\n" })
  ]])

  h.eq(file_res, "FILE:I am a file-based parser\n")
end

T["parsers.parser()"] = new_set()

T["parsers.parser()"]["uses file-level parser before group-level, otherwise returns content"] = function()
  child.lua([[
    package.loaded['codecompanion.config'] = {
      rules = {
        parsers = {
          file_parser = { content = function(p) return "FILE:" .. (p.content or "") end },
          group_parser = { content = function(p) return "GROUP:" .. (p.content or "") end }
        }
      }
    }
  ]])

  local file_first = child.lua([[
    local parsers = require("codecompanion.interactions.chat.rules.parsers")
    return parsers.parse({ parser = "file_parser", content = "1\n" }, "group_parser")
  ]])
  h.eq(file_first.content, "1\n")

  local group_used = child.lua([[
    local parsers = require("codecompanion.interactions.chat.rules.parsers")
    return parsers.parse({ content = "2\n" }, "group_parser")
  ]])
  h.eq(group_used.content, "2\n")

  local raw = child.lua([[
    local parsers = require("codecompanion.interactions.chat.rules.parsers")
    return parsers.parse({ content = "RAW\n" }, nil)
  ]])
  h.eq(raw.content, "RAW\n")
end

return T
