---@class CodeCompanion.AdapterArgs
return {
  name = "jina",
  opts = {
    stream = false,
  },
  url = "",
  headers = {},
  schema = {
    model = {
      default = "jina",
    },
  },
  handlers = {},
  methods = {
    slash_commands = {
      ---@param self CodeCompanion.Adapter
      ---@param data table
      ---@return {data: table, status: string}|nil
      fetch = function(self, data)
        self.url = "https://r.jina.ai"

        self.handlers.set_body = function(s, d)
          return { url = d.url }
        end

        self.headers = vim.tbl_deep_extend("force", self.headers, {
          ["Content-Type"] = "application/json",
          ["X-Return-Format"] = "text",
          ["Accept"] = "application/json",
        })

        if self.env and self.env.api_key then
          self.headers = vim.tbl_deep_extend("force", self.headers, {
            ["Authorization"] = "Bearer ${api_key}",
          })
        end
      end,
    },
  },
}
