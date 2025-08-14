return {
  name = "tool_group_tool",
  cmds = {
    function()
      return "Tool group's tool executed"
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "tool_group_tool",
      description = "Tool group's tool",
      parameters = {
        type = "object",
        properties = {},
      },
    },
  },
}
