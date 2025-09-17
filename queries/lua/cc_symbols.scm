; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/lua/aerial.scm
; MIT License

(variable_declaration
  (assignment_statement
    (expression_list
      value: (_) @name))
  (#contains? @name "require")
  (#set! "kind" "Import")) @symbol

(function_declaration
  name: [
    (identifier)
    (dot_index_expression)
    (method_index_expression)
  ] @name
  (#set! "kind" "Function")) @symbol
