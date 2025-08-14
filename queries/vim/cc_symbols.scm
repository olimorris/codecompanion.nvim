; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/vim/aerial.scm
; MIT License

(function_definition
  (function_declaration
    name: [
      (identifier)
      (scoped_identifier)
    ] @name)
  (#set! "kind" "Function")) @symbol

(function_definition
  (function_declaration
    name: (field_expression) @name)
  (#set! "kind" "Function")) @symbol
