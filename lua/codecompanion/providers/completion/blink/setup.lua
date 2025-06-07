local blink = require("blink.cmp")

pcall(function()
  local add_provider = blink.add_source_provider or blink.add_provider --[[@type function]]
  add_provider("codecompanion", {
    name = "CodeCompanion",
    module = "codecompanion.providers.completion.blink",
    enabled = true,
    score_offset = 10,
  })
end)
pcall(function()
  blink.add_filetype_source("codecompanion", "codecompanion")
end)
