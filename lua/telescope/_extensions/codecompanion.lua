return require("telescope").register_extension({
  exports = {
    codecompanion = function(opts)
      return require("codecompanion").actions({ provider = { name = "telescope", opts = opts } })
    end,
  },
})
