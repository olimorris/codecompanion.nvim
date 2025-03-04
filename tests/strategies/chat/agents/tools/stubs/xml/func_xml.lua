local M = {}

function M.two_data_points(name)
  name = name or "func"

  return string.format(
    [[<tools>
  <tool name="%s">
    <action type="type1"><data>Data 1</data></action>
    <action type="type2"><data>Data 2</data></action>
  </tool>
</tools>]],
    name
  )
end

function M.one_data_point(name)
  name = name or "func"

  return string.format(
    [[<tools>
  <tool name="%s">
    <action type="type1"><data>Data 1</data></action>
  </tool>
</tools>]],
    name
  )
end

return M
