; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/cpp/aerial.scm
; MIT License

((preproc_include
   path: (_) @name)
  (#set! "kind" "Import")) @symbol

(struct_specifier
  name: (type_identifier) @name
  body: (field_declaration_list)
  (#set! "kind" "Struct")) @symbol

(declaration
  (struct_specifier
    body: (field_declaration_list)) @symbol
  declarator: (identifier) @name
  (#set! "kind" "Struct"))

(function_declarator
  declarator: (_) @name
  (#set! "kind" "Function")) @symbol

(enum_specifier
  name: (type_identifier) @name
  (#set! "kind" "Enum")) @symbol

(class_specifier
  name: (type_identifier) @name
  (#set! "kind" "Class")) @symbol
