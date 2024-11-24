local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")

---@class CodeCompanion.Cmd
local Cmd = {}

---@param args table
function Cmd.new(args)
  local self = setmetatable({
    context = args.context,
    prompts = args.prompts,
    opts = args.opts,
  }, { __index = Cmd })

  self.adapter = adapters.resolve(config.adapters[config.strategies.cmd.adapter])
  if not self.adapter then
    return log:error("No adapter found")
  end

  return self
end

---Make the request to the LLM and create the ex command
---@return nil
function Cmd:start()
  local messages = {}

  if config.strategies.cmd.opts.system_prompt and config.strategies.cmd.opts.system_prompt ~= "" then
    table.insert(messages, {
      role = config.constants.SYSTEM_ROLE,
      content = config.strategies.cmd.opts.system_prompt,
      opts = { visible = false },
    })
  end

  vim.iter(self.prompts):map(function(p)
    table.insert(messages, p)
  end)

  client.new({ adapter = self.adapter:map_schema_to_params() }):request(self.adapter:map_roles(messages), {
    ---@param err string
    ---@param data table
    callback = function(err, data)
      if err then
        return log:error(err)
      end

      if data then
        local result = self.adapter.handlers.chat_output(self.adapter, data)
        if result and result.output and result.output.content then
          local content = result.output.content
          content:gsub("^%s*(.-)%s*$", "%1")
          vim.api.nvim_feedkeys(content, "n", false)
        end
      end
    end,
    done = function() end,
  }, { bufnr = self.context.bufnr })
end

return Cmd
