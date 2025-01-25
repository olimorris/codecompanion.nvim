; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/typescript/aerial.scm
; MIT License

((import_statement) @name
 (#set! "kind" "Import")) @symbol

(function_signature
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(function_declaration
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(generator_function_declaration
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(class_declaration
  name: (type_identifier) @name
  (#set! "kind" "Class")) @symbol

(interface_declaration
  name: (type_identifier) @name
  (#set! "kind" "Interface")) @symbol

(method_definition
  name: (property_identifier) @name
  (#set! "kind" "Method")) @symbol

(public_field_definition
  name: (property_identifier) @name
  value: (arrow_function)
  (#set! "kind" "Method")) @symbol
