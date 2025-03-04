local log = require("codecompanion.utils.log")

return log.set_root(log.new({
  handlers = {
    {
      type = "file",
      filename = "codecompanion_test.log",
      level = vim.log.levels["DEBUG"],
    },
  },
}))
