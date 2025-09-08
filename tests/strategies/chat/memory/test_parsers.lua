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

T["parsers.resolve()"]["handles table and function entries"] = function()
  child.lua([[
    package.loaded['codecompanion.config'] = {
      memory = {
        parsers = {
          table_par = {
            content = function(p) return "T:" .. (p.content or "") end
          },
          fn_par = function()
            return { content = function(p) return "F:" .. (p.content or "") end }
          end
        }
      }
    }
  ]])

  local t_res = child.lua([[
    local parsers = require("codecompanion.strategies.chat.memory.parsers")
    local p = parsers.resolve("table_par")
    return p.content({ content = "a\n" })
  ]])
  h.eq(t_res, "T:a\n")

  local f_res = child.lua([[
    local parsers = require("codecompanion.strategies.chat.memory.parsers")
    local p = parsers.resolve("fn_par")
    return p.content({ content = "b\n" })
  ]])
  h.eq(f_res, "F:b\n")
end

T["parsers.resolve()"]["supports builtin module name and file-based parser"] = function()
  -- Mock the built-in parser module
  child.lua([[
    package.loaded["codecompanion.strategies.chat.memory.parsers.builtinmod"] = {
      content = function(p) return "BUILTIN:" .. (p.content or "") end
    }
    package.loaded['codecompanion.config'] = {
      memory = { parsers = { builtin_parser = "builtinmod" } }
    }
  ]])

  local built = child.lua([[
    local parsers = require("codecompanion.strategies.chat.memory.parsers")
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
      memory = { parsers = { file_parser = %q } }
    }
  ]],
    tmp
  ))

  child.lua([[ package.loaded['codecompanion.strategies.chat.memory.parsers'] = nil ]])

  local file_res = child.lua([[
    local parsers = require("codecompanion.strategies.chat.memory.parsers")
    local p = parsers.resolve("file_parser")
    return p.content({ content = "I am a file-based parser\n" })
  ]])

  h.eq(file_res, "FILE:I am a file-based parser\n")
end

T["parsers.parser()"] = new_set()

T["parsers.parser()"]["uses rule-level parser before group-level, otherwise returns content"] = function()
  child.lua([[
    package.loaded['codecompanion.config'] = {
      memory = {
        parsers = {
          rule_parser = { content = function(p) return "RULE:" .. (p.content or "") end },
          group_parser = { content = function(p) return "GROUP:" .. (p.content or "") end }
        }
      }
    }
  ]])

  local rule_first = child.lua([[
    local parsers = require("codecompanion.strategies.chat.memory.parsers")
    return parsers.parse({ parser = "rule_parser", content = "1\n" }, "group_parser")
  ]])
  h.eq(rule_first, "RULE:1\n")

  local group_used = child.lua([[
    local parsers = require("codecompanion.strategies.chat.memory.parsers")
    return parsers.parse({ content = "2\n" }, "group_parser")
  ]])
  h.eq(group_used, "GROUP:2\n")

  local raw = child.lua([[
    local parsers = require("codecompanion.strategies.chat.memory.parsers")
    return parsers.parse({ content = "RAW\n" }, nil)
  ]])
  h.eq(raw, "RAW\n")
end

return T
