local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
    post_once = child.stop,
  },
})

---@param str string
---@return table
local function decode(str)
  return child.lua("return require('codecompanion.utils.yaml').decode(...)", { str })
end

T["YAML utils"] = new_set()

T["YAML utils"]["decode"] = new_set()

T["YAML utils"]["decode"]["folds a > block scalar into one line per paragraph"] = function()
  local decoded = decode("description: >\n  Fill and inspect\n  PDF forms.\n\n  Use for forms.\nname: pdf")

  h.eq("Fill and inspect PDF forms.\nUse for forms.\n", decoded.description)
  h.eq("pdf", decoded.name)
end

T["YAML utils"]["decode"]["keeps the more-indented lines of a > block scalar on their own lines"] = function()
  local decoded = decode("description: >\n  Steps:\n    - one\n    - two\n  Done.")

  h.eq("Steps:\n  - one\n  - two\nDone.\n", decoded.description)
end

T["YAML utils"]["decode"]["keeps the newlines of a | block scalar"] = function()
  local decoded = decode("script: |\n  echo one\n    echo two\n\n  echo three")

  h.eq("echo one\n  echo two\n\necho three\n", decoded.script)
end

T["YAML utils"]["decode"]["strips the final newline of a >- block scalar"] = function()
  local decoded = decode("description: >-\n  Fill and inspect\n  PDF forms")

  h.eq("Fill and inspect PDF forms", decoded.description)
end

return T
