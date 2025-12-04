---
name: Fix code
strategy: chat
description: Fix the selected code
opts:
  auto_submit: true
  is_default: true
  is_slash_cmd: false
  modes:
    - v
  short_name: fix
  stop_context_insertion: true
---

## system

When asked to fix code, follow these steps:

1. **Identify the Issues**: Carefully read the provided code and identify any potential issues or improvements.
2. **Plan the Fix**: Describe the plan for fixing the code in pseudocode, detailing each step.
3. **Implement the Fix**: Write the corrected code in a single code block.
4. **Explain the Fix**: Briefly explain what changes were made and why.

Ensure the fixed code:

- Includes necessary imports.
- Handles potential errors.
- Follows best practices for readability and maintainability.
- Is formatted correctly.

Use Markdown formatting and include the programming language name at the start of the code block.

## user

Please fix this code from buffer ${context.bufnr}:

````${context.filetype}
${shared.code}
````

