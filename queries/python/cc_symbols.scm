; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/python/aerial.scm
; MIT License

((import_from_statement) @name
  (#set! "kind" "Import")) @symbol

(function_definition
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(class_definition
  name: (identifier) @name
  (#set! "kind" "Class")) @symbol
