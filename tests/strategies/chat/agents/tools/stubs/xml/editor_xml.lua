local M = {}

function M.update(bufnr)
  return string.format(
    [[
<tools>
  <tool name="editor">
    <action type="update">
      <start_line>2</start_line>
      <end_line>2</end_line>
      <buffer>%s</buffer>
      <code>%s</code>
    </action>
  </tool>
</tools>
]],
    bufnr,
    '<![CDATA[    return "foobar"]]>'
  )
end

function M.add(bufnr)
  return string.format(
    [[
<tools>
  <tool name="editor">
    <action type="add">
      <line>4</line>
      <buffer>%s</buffer>
      <code>%s</code>
    </action>
  </tool>
</tools>
]],
    bufnr,
    [[function hello_world()
    return "hello_world"
end]]
  )
end

function M.delete(bufnr)
  return string.format(
    [[
<tools>
  <tool name="editor">
    <action type="delete">
      <start_line>1</start_line>
      <end_line>4</end_line>
      <buffer>%s</buffer>
    </action>
  </tool>
</tools>
]],
    bufnr
  )
end

return M
