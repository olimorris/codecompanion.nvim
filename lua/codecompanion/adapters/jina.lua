---@class CodeCompanion.AdapterArgs
return {
  name = "jina",
  opts = {
    stream = false,
  },
  url = "https://r.jina.ai",
  headers = {
    ["Content-Type"] = "application/json",
    ["X-Return-Format"] = "text",
    ["Accept"] = "application/json",
  },
  schema = {
    model = {
      default = "jina",
    },
  },
  handlers = {
    set_body = function(self, data)
      return { url = data.url }
    end,
  },
}
