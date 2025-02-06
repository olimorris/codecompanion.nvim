(section
  (atx_heading
    (atx_h2_marker)
    heading_content: (_) @role
  )
) @content

(section
  (atx_heading) @role
  (#eq? @role "Response")
) @content

(section
  (fenced_code_block
    (info_string) @lang
    (code_fence_content) @tool
  )(#match? @lang "xml")
)
