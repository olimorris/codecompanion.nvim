local M = {}

function M.load(name)
  name = name or "cmd"
  return string.format(
    [[<tools>
  <tool name="%s"></tool>
</tools>]],
    name
  )
end

function M.multiple(tool1, tool2)
  tool1 = tool1 or "cmd"
  tool2 = tool2 or "cmd"
  return string.format(
    [[<tools>
  <tool name="%s"></tool>
  <tool name="%s"></tool>
</tools>]],
    tool1,
    tool2
  )
end

function M.test_flag()
  return [[<tools>
  <tool name="mock_cmd_runner">
    <action>
      <command>echo Hello World</command>
      <flag>testing</flag>
    </action>
  </tool>
</tools>]]
end

return M
