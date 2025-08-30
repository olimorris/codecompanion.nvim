local file_utils = require("codecompanion.utils.files")

local M = {}

---@param self CodeCompanion.ACPAdapter
---@param messages table
---@return table
M.form_messages = function(self, messages)
  return vim
    .iter(messages)
    :filter(function(msg)
      -- Ensure we're only sending messages that the agent hasn't seen before
      return msg.role == self.roles.user and not msg._meta.sent
    end)
    :map(function(msg)
      if msg.opts and msg.opts.tag == "image" then
        return {
          type = "image",
          data = msg.content,
          mimeType = msg.opts.mimetype,
        }
      end
      if msg.content and msg.content ~= "" then
        if msg.opts and msg.opts.tag == "file" then
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
