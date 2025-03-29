; Expanded from Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/java/aerial.scm
; MIT License

(package_declaration
  (scoped_identifier) @name
  (#set! "kind" "Import")) @symbol

(import_declaration
  (scoped_identifier) @name
  (#set! "kind" "Import")) @symbol

(interface_declaration
  name: (identifier) @name
  (#set! "kind" "Interface")) @symbol

(method_declaration
  name: (identifier) @name @start
  (#set! "kind" "Method")) @symbol

(class_declaration
  name: (identifier) @name
  (#set! "kind" "Class")) @symbol

(record_declaration
  name: (identifier) @name
  (#set! "kind" "Class")) @symbol

(enum_declaration
  name: (identifier) @name
  (#set! "kind" "Enum")) @symbol

