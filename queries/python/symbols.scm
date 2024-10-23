; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/python/aerial.scm
; MIT License

(function_definition
  name: (identifier) @name
  (#set! "kind" "Function")) @symbol

(class_definition
  name: (identifier) @name
  (#set! "kind" "Class")) @symbol
