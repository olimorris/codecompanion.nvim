; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/javascript/aerial.scm
; MIT License

((import_statement) @name
 (#set! "kind" "Import")) @symbol

(class_declaration
  name: (identifier) @name
  (#set! "kind" "Class")) @symbol

(function_declaration
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(generator_function_declaration
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(method_definition
  name: (property_identifier) @name
  (#set! "kind" "Method")) @symbol

(field_definition
  property: (property_identifier) @name
  value: (arrow_function)
  (#set! "kind" "Method")) @symbol
