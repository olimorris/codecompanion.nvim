---
name: Test Context
strategy: chat
description: Test the context
opts:
  auto_submit: false
  is_default: true
  is_slash_cmd: true
  short_name: commit
context:
  - type: file
    path:
      - lua/codecompanion/health.lua
      - lua/codecompanion/http.lua
---

## user

You are an expert at following the Conventional Commit specification. Given the git diff listed below, please generate a commit message for me:


