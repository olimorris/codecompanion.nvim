local new_set = MiniTest.new_set
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    post_once = child.stop,
  },
})

T["Skills"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
  },
})

---@param dirs string[]
local function list_skills(dirs)
  return child.lua(string.format(
    [[
      package.loaded["codecompanion.config"] = { skills = { dirs = %s } }
      return require("codecompanion.skills").list()
    ]],
    vim.inspect(dirs)
  ))
end

T["Skills"]["discovers only the skills with a name and a description"] = function()
  local skills = list_skills({ "tests/stubs/skills/personal" })

  h.eq(2, #skills)
  h.eq("house-style", skills[1].name)
  h.eq("Lua conventions for this project", skills[1].description)
  h.eq("pdf-forms", skills[2].name)
  h.eq("Fill and inspect PDF forms", skills[2].description)
  h.expect_match(skills[2].path, "tests/stubs/skills/personal/pdf%-forms/SKILL%.md$")
end

T["Skills"]["skips a skill whose name is not a string"] = function()
  local skills = list_skills({ "tests/stubs/skills/personal" })

  local names = vim.tbl_map(function(skill)
    return skill.name
  end, skills)
  h.eq(false, vim.tbl_contains(names, true))
  h.eq(2, #skills)
end

T["Skills"]["a later dir overrides a skill with the same name"] = function()
  local skills = list_skills({ "tests/stubs/skills/personal", "tests/stubs/skills/project" })

  h.eq(2, #skills)
  h.eq("house-style", skills[1].name)
  h.eq("Lua conventions from the project directory", skills[1].description)
end

T["Skills"]["keeps discovering when a configured dir doesn't exist"] = function()
  local skills = list_skills({ "tests/stubs/skills/does-not-exist", "tests/stubs/skills/personal" })

  h.eq(2, #skills)
end

T["Skills in a chat"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        _G.chat = h.setup_chat_buffer()

        local config = require("codecompanion.config")
        config.skills.dirs = { "tests/stubs/skills/personal" }
        config.skills["Senior Engineer"] = {
          description = "Skills for a senior engineer",
          skills = { "house-style", "pdf-forms" },
        }

        _G.skills = require("codecompanion.skills")
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
  },
})

T["Skills in a chat"]["names the skill and points at its SKILL.md"] = function()
  child.lua([[_G.skills.add_to_chat(_G.chat, _G.skills.resolve({ "pdf-forms" }))]])

  local content = child.lua_get([[_G.chat.messages[#_G.chat.messages].content]])
  h.expect_contains("pdf-forms", content)
  h.expect_contains("Fill and inspect PDF forms", content)
  h.expect_match(content, "tests/stubs/skills/personal/pdf%-forms/SKILL%.md")
end

T["Skills in a chat"]["attaches the tools the model needs to load a skill"] = function()
  child.lua([[_G.skills.add_to_chat(_G.chat, _G.skills.resolve({ "pdf-forms" }))]])

  h.eq(true, child.lua_get([[_G.chat.tool_registry.in_use.read_file]]))
  h.eq(true, child.lua_get([[_G.chat.tool_registry.in_use.run_command]]))
end

T["Skills in a chat"]["DOES NOT add a skill when `read_file` is disabled"] = function()
  child.lua([[
    _G.chat.tools.tools_config.read_file = nil
    _G.skills.add_to_chat(_G.chat, _G.skills.resolve({ "pdf-forms" }))
  ]])

  h.eq(0, child.lua_get([[#_G.chat.context_items]]))
  h.eq(vim.NIL, child.lua_get([[_G.chat.tool_registry.in_use.read_file]]))
end

T["Skills in a chat"]["adds a skill without `run_command` when it is disabled"] = function()
  child.lua([[
    _G.chat.tools.tools_config.run_command = nil
    _G.skills.add_to_chat(_G.chat, _G.skills.resolve({ "pdf-forms" }))
  ]])

  h.eq(true, child.lua_get([[_G.chat.tool_registry.in_use.read_file]]))
  h.eq(vim.NIL, child.lua_get([[_G.chat.tool_registry.in_use.run_command]]))
end

T["Skills in a chat"]["a group adds every skill it names"] = function()
  child.lua([[_G.skills.add_to_chat(_G.chat, _G.skills.resolve({ "Senior Engineer" }))]])

  local ids = child.lua_get([[
    vim.tbl_map(function(item) return item.id end, _G.chat.context_items)
  ]])
  h.eq(true, vim.tbl_contains(ids, "<skill>house-style</skill>"))
  h.eq(true, vim.tbl_contains(ids, "<skill>pdf-forms</skill>"))
end

T["Skills in a chat"]["adding the same skill twice adds it once"] = function()
  child.lua([[
    _G.skills.add_to_chat(_G.chat, _G.skills.resolve({ "pdf-forms" }))
    _G.skills.add_to_chat(_G.chat, _G.skills.resolve({ "pdf-forms" }))
  ]])

  local count = child.lua_get([[
    #vim.tbl_filter(function(item)
      return item.id == "<skill>pdf-forms</skill>"
    end, _G.chat.context_items)
  ]])
  h.eq(1, count)
end

T["Skills in a chat"]["DOES NOT add skills when the adapter has no tool support"] = function()
  child.lua([[
    _G.chat.adapter.opts.tools = false
    _G.skills.add_to_chat(_G.chat, _G.skills.resolve({ "pdf-forms" }))
  ]])

  h.eq(0, child.lua_get([[#_G.chat.context_items]]))
end

T["Skills in a chat"]["autoload adds the configured skills to a new chat"] = function()
  local ids = child.lua([[
    local config = require("codecompanion.config")
    config.skills.opts.chat.autoload = { "Senior Engineer" }

    local chat = require("codecompanion.interactions.chat").new({
      buffer_context = { bufnr = 1, filetype = "lua" },
      adapter = "test_adapter",
    })
    return vim.tbl_map(function(item) return item.id end, chat.context_items)
  ]])

  h.eq(true, vim.tbl_contains(ids, "<skill>house-style</skill>"))
  h.eq(true, vim.tbl_contains(ids, "<skill>pdf-forms</skill>"))
end

return T
