return {
  code = function(context)
    return require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)
  end,
}
