; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/go/aerial.scm
; MIT License

((package_clause) @name
  (#set! "kind" "Import")) @symbol
(import_spec_list
   (import_spec) @name
  (#set! "kind" "Import")) @symbol

(function_declaration
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(type_declaration
  (type_spec
    name: (type_identifier) @name
    type: (struct_type) @symbol)
  (#set! "kind" "Struct")) @start

(type_declaration
  (type_spec
    name: (type_identifier) @name
    type: (interface_type) @symbol)
  (#set! "kind" "Interface")) @start

(method_declaration
  receiver: (_) @receiver
  name: (field_identifier) @name
  (#set! "kind" "Method")) @symbol
