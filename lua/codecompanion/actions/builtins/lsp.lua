return {
  diagnostics = function(args)
    local diagnostics = require("codecompanion.helpers.actions").get_diagnostics(
      args.context.start_line,
      args.context.end_line,
      args.context.bufnr
    )

    local concatenated_diagnostics = ""
    for i, diagnostic in ipairs(diagnostics) do
      concatenated_diagnostics = concatenated_diagnostics
        .. i
        .. ". Issue "
        .. i
        .. "\n  - Location: Line "
        .. diagnostic.line_number
        .. "\n  - Buffer: "
        .. args.context.bufnr
        .. "\n  - Severity: "
        .. diagnostic.severity
        .. "\n  - Message: "
        .. diagnostic.message
        .. "\n"
    end

    return concatenated_diagnostics
  end,
}
