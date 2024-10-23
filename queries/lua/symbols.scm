; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/lua/aerial.scm
; MIT License

(function_declaration
  name: [
    (identifier)
    (dot_index_expression)
    (method_index_expression)
  ] @name
  (#set! "kind" "Function")) @symbol
