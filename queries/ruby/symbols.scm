; Ref: https://github.com/stevearc/aerial.nvim/blob/master/queries/ruby/aerial.scm
; MIT License

; Module definitions
(module
  name: [
    (constant)
    (scope_resolution)
  ] @name
  (#set! "kind" "Module")) @symbol

; Class definitions
(class
  name: [
    (constant)
    (scope_resolution)
  ] @name
  (#set! "kind" "Class")) @symbol

(singleton_class
  value: (_) @name
  (#set! "kind" "Class")) @symbol

; Method definitions
(singleton_method
  object: [
    (constant)
    (self)
    (identifier)
  ] @receiver
  ([
    "."
    "::"
  ] @separator)?
  name: [
    (operator)
    (identifier)
  ] @name
  (#set! "kind" "Method")) @symbol

(body_statement
  [
    (_)
    ((identifier) @scope
      (#any-of? @scope "private" "protected" "public"))
  ]*
  .
  (method
    name: (_) @name
    (#set! "kind" "Method")) @symbol)
