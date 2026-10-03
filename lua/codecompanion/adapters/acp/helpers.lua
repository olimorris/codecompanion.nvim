local log = require("codecompanion.utils.log")
local tags = require("codecompanion.interactions.shared.tags")

local M = {}

---@param self CodeCompanion.ACPAdapter
---@param args { messages: table, capabilities: ACP.agentCapabilities }
---@return table
M.build_messages = function(self, args)
  local has = args.capabilities and args.capabilities.promptCapabilities

  return vim
    .iter(args.messages)
    :filter(function(msg)
      -- Ensure we're only sending messages that the agent hasn't seen before
      return msg.role == self.roles.user and msg._meta and not msg._meta.sent
    end)
    :map(function(msg)
      if msg._meta and msg._meta.tag == tags.IMAGE and msg.context and msg.context.mimetype then
        if not has.image then
          log:warn("The %s agent does not support receiving images", self.formatted_name)
        else
          return {
            type = "image",
            data = msg.content,
            mimeType = msg.context.mimetype,
          }
        end
      end
      if msg.content and msg.content ~= "" then
        if msg._meta and (msg._meta.tag == tags.FILE or msg._meta.tag == tags.BUFFER) then
          if msg.context and msg.context.path then
            return {
              type = "text",
              text = string.format([[Sharing the following file as context: %s]], msg.context.path),
            }
          end
        else
          return {
            type = "text",
            text = msg.content,
          }
        end
      end
    end)
    :totable()
end

---@deprecated Use `build_messages`, which takes an args table
---@param self CodeCompanion.ACPAdapter
---@param messages table
---@param capabilities ACP.agentCapabilities
---@return table
M.form_messages = function(self, messages, capabilities)
  return M.build_messages(self, { messages = messages, capabilities = capabilities })
end

return M
