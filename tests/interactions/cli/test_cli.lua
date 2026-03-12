local new_set = MiniTest.new_set
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        local config = require("codecompanion.config")
        config.interactions.cli.agents = {
          test_agent_a = { cmd = "cat", args = {}, description = "Agent A" },
          test_agent_b = { cmd = "cat", args = {}, description = "Agent B" },
        }
        config.interactions.cli.agent = "test_agent_a"
        h.setup_plugin(config)
      ]])
    end,
    pre_case = function()
      -- Clean up any CLI instances between tests
      child.lua([[
        local cli = require("codecompanion.interactions.cli")
        -- Close all instances by toggling/finding visible ones
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          local name = vim.api.nvim_buf_get_name(bufnr)
          if name:find("%[CodeCompanion CLI%]") then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
          end
        end
        -- Reset module state by re-requiring
        package.loaded["codecompanion.interactions.cli"] = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["CLI"] = new_set()

T["CLI"]["create() returns a CLI instance"] = function()
  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")
    local instance = cli.create({ agent = "test_agent_a" })
    return {
      created = instance ~= nil,
      agent_name = instance and instance.agent_name,
      bufnr_type = instance and type(instance.bufnr),
    }
  ]])

  h.eq(true, result.created)
  h.eq("test_agent_a", result.agent_name)
  h.eq("number", result.bufnr_type)
end

T["CLI"]["create() makes distinct instances for different agents"] = function()
  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")
    local a = cli.create({ agent = "test_agent_a" })
    local b = cli.create({ agent = "test_agent_b" })
    return {
      both_created = a ~= nil and b ~= nil,
      different_bufnr = a.bufnr ~= b.bufnr,
      a_agent = a.agent_name,
      b_agent = b.agent_name,
    }
  ]])

  h.eq(true, result.both_created)
  h.eq(true, result.different_bufnr)
  h.eq("test_agent_a", result.a_agent)
  h.eq("test_agent_b", result.b_agent)
end

T["CLI"]["create() allows multiple instances of the same agent"] = function()
  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")
    local a1 = cli.create({ agent = "test_agent_a" })
    local a2 = cli.create({ agent = "test_agent_a" })
    return {
      both_created = a1 ~= nil and a2 ~= nil,
      different_bufnr = a1.bufnr ~= a2.bufnr,
    }
  ]])

  h.eq(true, result.both_created)
  h.eq(true, result.different_bufnr)
end

T["CLI"]["last_cli() returns the most recently created instance"] = function()
  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")
    local a = cli.create({ agent = "test_agent_a" })
    local b = cli.create({ agent = "test_agent_b" })
    local last = cli.last_cli()
    return {
      last_bufnr = last and last.bufnr,
      b_bufnr = b.bufnr,
    }
  ]])

  h.eq(result.b_bufnr, result.last_bufnr)
end

T["CLI"]["find_by_agent() returns the correct instance"] = function()
  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")
    local a = cli.create({ agent = "test_agent_a" })
    local b = cli.create({ agent = "test_agent_b" })
    local found = cli.find_by_agent("test_agent_a")
    return {
      found_bufnr = found and found.bufnr,
      a_bufnr = a.bufnr,
    }
  ]])

  h.eq(result.a_bufnr, result.found_bufnr)
end

T["CLI"]["find_by_agent() returns nil for unknown agent"] = function()
  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")
    cli.create({ agent = "test_agent_a" })
    local found = cli.find_by_agent("nonexistent")
    return found == nil
  ]])

  h.eq(true, result)
end

T["CLI"]["close() removes instance and clears last_cli"] = function()
  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")
    local instance = cli.create({ agent = "test_agent_a" })
    instance:close()
    return {
      last_is_nil = cli.last_cli() == nil,
      find_is_nil = cli.find_by_agent("test_agent_a") == nil,
    }
  ]])

  h.eq(true, result.last_is_nil)
  h.eq(true, result.find_is_nil)
end

T["CLI"]["close() preserves other instances"] = function()
  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")
    local a = cli.create({ agent = "test_agent_a" })
    local b = cli.create({ agent = "test_agent_b" })
    b:close()
    return {
      a_still_findable = cli.find_by_agent("test_agent_a") ~= nil,
      b_gone = cli.find_by_agent("test_agent_b") == nil,
    }
  ]])

  h.eq(true, result.a_still_findable)
  h.eq(true, result.b_gone)
end

T["CLI"]["create() returns nil for unknown agent"] = function()
  local result = child.lua([[
    local cli = require("codecompanion.interactions.cli")
    local instance = cli.create({ agent = "nonexistent_agent" })
    return instance == nil
  ]])

  h.eq(true, result)
end

return T
