---
strategy: chat
name: Commit Message
description: Generate a commit message
opts:
  auto_submit: false
  is_default: true
  is_slash_cmd: true
  short_name: commit
---

## user

You are an expert at following the Conventional Commit specification. Given the git diff listed below, please generate a commit message for me:

`````diff
${commit.diff}
`````

