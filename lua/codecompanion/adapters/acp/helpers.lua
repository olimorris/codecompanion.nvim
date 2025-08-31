local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local M = {}

---@param self CodeCompanion.ACPAdapter
---@param messages table
---@param capabilities {}
---@return table
M.form_messages = function(self, messages, capabilities)
  local has = capabilities and capabilities.promptCapabilities

  return vim
    .iter(messages)
    :filter(function(msg)
      -- Ensure we're only sending messages that the agent hasn't seen before
      return msg.role == self.roles.user and not msg._meta.sent
    end)
    :map(function(msg)
      if msg.opts and msg.opts.tag == "image" then
        if not has.image then
          log:warn("The %s agent does not support receiving images", self.formatted_name)
        else
          return {
            type = "image",
            data = msg.content,
            mimeType = msg.opts.mimetype,
          }
        end
      end
      if msg.content and msg.content ~= "" then
        if msg.opts and msg.opts.tag == "file" then
          -- If we can't send the file as a resource, send as text
          if not has.embeddedContext then
            log:debug(
              "[adapters::acp::helpers] The %s agent does not support embedded context, sending file content as text",
              self.formatted_name
            )
            return {
              type = "text",
              text = msg.content,
            }
          end
          -- NOTE: I HATE having to re-read a file that's already been read and
          -- loaded into the chat buffer as context. Alas, for http adapters
          -- the context is wrapped in <attachment> tags so it's clearer
          -- to the LLM what we're sending. But this doesn't make much
          -- sense for ACP clients, hence the file utils read here.
          local ok, file_content = pcall(file_utils.read, msg.opts.absolute_path)
          if ok then
            return {
              type = "resource",
              resource = {
                uri = "file://" .. msg.opts.absolute_path,
                text = file_content,
              },
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

return M
