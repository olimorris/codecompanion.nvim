; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/php/aerial.scm
; MIT License

((require_expression) @name
 (#set! "kind" "Import")) @symbol

((require_once_expression) @name
 (#set! "kind" "Import")) @symbol

((include_expression) @name
 (#set! "kind" "Import")) @symbol

((include_once_expression) @name
 (#set! "kind" "Import")) @symbol

(function_definition
  name: (name) @name
  (#set! "kind" "Function")) @symbol

(expression_statement
  (assignment_expression
    left: (variable_name) @name
    right: (anonymous_function) @symbol)
  (#set! "kind" "Function")) @start

(class_declaration
  name: (name) @name
  (#set! "kind" "Class")) @symbol

(method_declaration
  ((visibility_modifier) @scope)?
  name: (name) @name
  (#set! "kind" "Method")) @symbol

(trait_declaration
  name: (name) @name
  (#set! "kind" "Class")) @symbol
