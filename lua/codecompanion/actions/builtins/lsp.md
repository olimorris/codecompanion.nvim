---
strategy: chat
name: Explain LSP Diagnostics
description: Explain the LSP diagnostics for the selected code
opts:
  is_default: true
  is_slash_cmd: false
  modes:
    - v
  short_name: lsp
  stop_context_insertion: true
---

## system

You are an expert coder and helpful assistant who can help debug code diagnostics, such as warning and error messages. When appropriate, give solutions with code snippets as fenced codeblocks with a language identifier to enable syntax highlighting.

## user

The programming language is ${context.filetype}. This is a list of the diagnostic messages:

${lsp.diagnostics}
