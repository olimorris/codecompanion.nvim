; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/scala/aerial.scm
; MIT License
(package_clause
  name: (package_identifier) @name
  (#set! "kind" "Import")) @symbol

(import_declaration
  path: (identifier) @name
  (#set! "kind" "Import")) @symbol

(trait_definition
  name: (identifier) @name
  (#set! "kind" "Interface")) @symbol

(object_definition
  name: (identifier) @name
  (#set! "kind" "Class")) @symbol

(class_definition
  name: (identifier) @name
  (#set! "kind" "Class")) @symbol

(function_declaration
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(function_definition
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol
