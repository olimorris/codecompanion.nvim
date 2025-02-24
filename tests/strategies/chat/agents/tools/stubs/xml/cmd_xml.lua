local M = {}

function M.load(name)
  return string.format(
    [[<tools>
  <tool name="%s"></tool>
</tools>]],
    name
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
