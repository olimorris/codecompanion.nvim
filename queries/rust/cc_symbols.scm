; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/rust/aerial.scm
; MIT License

(use_declaration
   argument: (_) @name
 (#set! "kind" "Import")) @symbol

(mod_item
  name: (identifier) @name
  (#set! "kind" "Module")) @symbol

(enum_item
  name: (type_identifier) @name
  (#set! "kind" "Enum")) @symbol

(struct_item
  name: (type_identifier) @name
  (#set! "kind" "Struct")) @symbol

(function_item
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(function_signature_item
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(trait_item
  name: (type_identifier) @name
  (#set! "kind" "Interface")) @symbol

(impl_item
  trait: (type_identifier)? @trait
  type: (type_identifier) @name
  (#set! "kind" "Class")) @symbol

(impl_item
  trait: (type_identifier)? @trait
  type: (generic_type
    type: (type_identifier) @name)
  (#set! "kind" "Class")) @symbol
