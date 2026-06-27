local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")

---@class CodeCompanion.Cmd
---@field adapter CodeCompanion.HTTPAdapter The adapter to use for the chat
---@field buffer_context table The context of the buffer that the chat was initiated from
---@field prompts table Any prompts to be sent to the LLM

---@class CodeCompanion.Cmd
local Cmd = {}

---@param args table
function Cmd.new(args)
  local self = setmetatable({
    buffer_context = args.buffer_context,
    prompts = args.prompts,
    opts = args.opts,
  }, { __index = Cmd })

  self.adapter = adapters.resolve(config.interactions.cmd.adapter)
  if not self.adapter then
    return log:error("[Command] No adapter found")
  end
  if self.adapter.type ~= "http" then
    return log:warn("Only HTTP adapters are supported for command interactions")
  end

  -- Check if the user has manually overridden the adapter
  if vim.g.codecompanion_adapter and self.adapter.name ~= vim.g.codecompanion_adapter then
    self.adapter = adapters.resolve(config.adapters[vim.g.codecompanion_adapter])
  end

  return self
end

---Make the request to the LLM and create the ex command
---@return nil
function Cmd:start()
  local messages = {}

  if config.interactions.cmd.opts.system_prompt and config.interactions.cmd.opts.system_prompt ~= "" then
    table.insert(messages, {
      role = config.constants.SYSTEM_ROLE,
      content = config.interactions.cmd.opts.system_prompt,
      opts = { visible = false },
    })
  end

  vim.iter(self.prompts):map(function(p)
    table.insert(messages, p)
  end)

  -- The command is parsed from a single response, so we don't stream it back
  self.adapter.opts.stream = false

  client
    .new({ adapter = self.adapter:map_schema_to_params() })
    :stream({ messages = self.adapter:map_roles(messages) }, {
      bufnr = self.buffer_context.bufnr,
      interaction = "cmd",
      on_error = function(err)
        return log:error(err)
      end,
      on_done = function(data, meta)
        if not data then
          return
        end
        local result = adapters.call_handler(meta.adapter, "parse_chat", data)
        if result and result.output and result.output.content then
          local content = result.output.content
          content:gsub("^%s*(.-)%s*$", "%1")
          vim.api.nvim_feedkeys(content, "n", false)
        end
      end,
    })
end

return Cmd
