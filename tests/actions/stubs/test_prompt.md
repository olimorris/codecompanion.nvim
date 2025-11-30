---
name: Test Prompt
strategy: chat
description: Explain how code in a buffer works
opts:
  auto_submit: true
  is_default: true
  is_slash_cmd: true
  modes:
    - v
  short_name: explain
  stop_context_insertion: true
  user_prompt: false
---

## system

You are a helpful assistant.

## user

Explain the following code:

```python
def hello_world():
    print("Hello, world!")
```

## user

Here is another user prompt.

