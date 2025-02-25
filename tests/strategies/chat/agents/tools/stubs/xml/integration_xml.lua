local M = {}

function M.run(name)
  return string.format(
    [[<tools>
  <tool name="func_integration">
    <action type="type1"><data>Data 1</data></action>
  </tool>
  <tool name="cmd_integration"></tool>
  <tool name="func_integration_2">
    <action type="type1"><data>Data 2</data></action>
  </tool>
</tools>]],
    name
  )
end

return M
