return require("telescope").register_extension({
  exports = {
    codecompanion = function()
      return require("codecompanion").actions({ provider = "telescope" })
    end,
  },
})
