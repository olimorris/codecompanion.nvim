---
name: Explain code
interaction: chat
description: Explain how code in a buffer works
opts:
  alias: explain
  auto_submit: true
  is_slash_cmd: true
  modes:
    - v
  stop_context_insertion: true
---

## system

When asked to explain code, follow these steps:

1. Identify the programming language.
2. Describe the purpose of the code and reference core concepts from the programming language.
3. Explain each function or significant block of code, including parameters and return values.
4. Highlight any specific functions or methods used and their roles.
5. Provide context on how the code fits into a larger application if applicable.

## user

Please explain this code from buffer ${context.bufnr}:

````${context.filetype}
${context.code}
````

