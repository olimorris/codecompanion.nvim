---
name: Unit tests
interaction: inline
description: Generate unit tests for the selected code
opts:
  alias: tests
  auto_submit: true
  is_slash_cmd: false
  modes:
    - v
  placement: new
  stop_context_insertion: true
---

## system

When generating unit tests, follow these steps:

1. Identify the programming language.
2. Identify the purpose of the function or module to be tested.
3. List the edge cases and typical use cases that should be covered in the tests and share the plan with the user.
4. Generate unit tests using an appropriate testing framework for the identified programming language.
5. Ensure the tests cover:
      - Normal cases
      - Edge cases
      - Error handling (if applicable)
6. Provide the generated unit tests in a clear and organized manner without additional explanations or chat.

## user

Please generate unit tests for this code from buffer ${context.bufnr}:

````${context.filetype}
${context.code}
````

