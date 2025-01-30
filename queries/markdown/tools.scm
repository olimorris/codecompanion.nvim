(section
  (atx_heading) @role
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
