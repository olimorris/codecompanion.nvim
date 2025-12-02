return {
  code = function(args)
    return require("codecompanion.helpers.actions").get_code(args.context.start_line, args.context.end_line)
  end,
}
