The insert_edit_into_file tool performs deterministic file edits using text-based matching. It supports exact, block, or substring replacements with optional context matching for safety.
Use edit_tool_exp for safe, reliable file editing with advanced matching strategies.

# Quick Reference
✓ **Correct structure:**
```json
{
  "filepath": "path/to/file.js",
  "edits": [
    {
      "oldText": "function getName() {\n  return this.name;\n}",
      "newText": "function getFullName() {\n  return this.firstName + ' ' + this.lastName;\n}"
    }
  ],
  "explanation": "Renamed function from getName to getFullName and updated return value to concatenate first and last names"
}
```

# CRITICAL: Schema Requirements
Every edit MUST have both `oldText` AND `newText` - NO EXCEPTIONS.
- ✓ Preserve exact indentation (tabs/spaces) as it appears in the file

❌ **Common mistakes that cause FAILURE:**
- Missing `oldText` or `newText` fields
- Putting `filepath` or `explanation` inside the `edits` array
- Making `edits` a string instead of an array
- Using single quotes instead of double quotes in JSON
- Including line numbers in `oldText` (e.g., "117: function test()")

# How Matching Works

The tool uses different strategies based on your parameters:

**Standard matching (default):**
- Finds and replaces text using block/line matching with context
- Uses exact matching first, then tries whitespace normalization and block anchoring

**Substring matching (efficient token replacement):**
- Activated when: `replaceAll: true` AND `oldText` contains NO `\n` characters
- Finds ALL plain-text occurrences within the file (max 1000 replacements)
- Perfect for: renaming variables, updating keywords (var→let), API changes

**Block replace all:**
- Activated when: `replaceAll: true` AND `oldText` contains `\n` characters
- Replaces all matching code blocks/structures
# When to Use What

| Goal | Method |
|------|--------|
| Single specific change | Standard replacement with unique context |
| Same change everywhere (blocks/structures) | `replaceAll: true` with `\n` in oldText |
| Same change everywhere (tokens/keywords) | `replaceAll: true` without `\n` in oldText (max 1000) |
| Multiple different changes | Multiple edits in array (applied sequentially) |
| Add to start of file | `oldText: "^"` |
| Add to end of file | `oldText: "$"` |
| Initialize empty file contents | `oldText: ""` with initial content |
| Replace entire file contents | `mode: "overwrite"` |

# Performance Notes

- Substring replacement with `replaceAll: true` is limited to 1000 replacements per edit
- For large-scale refactoring, consider breaking into multiple insert_edit_into_file calls
- Sequential edits in one call are more efficient than multiple separate calls

# Parameters

- **filepath** (required): Path to file including extension
- **edits** (required): Array of edit objects, each with:
  - **oldText** (required): Exact text to find from file (preserve indentation exactly)
  - **newText** (required): Replacement text (empty string for deletion)
  - **replaceAll** (optional): true = replace all occurrences, false (default) = single/best match
- **mode** (optional): "append" (default) or "overwrite"
- **explanation** (strongly recommended): Brief, clear description of what the edits accomplish and why. While optional, providing an explanation helps with:

# Edit Operations

## 1. Standard Replacement
Replace a specific code block. Include enough context to make it unique.

```json
{
  "filepath": "config.js",
  "edits": [
    {
      "oldText": "const PORT = 3000;\nconst DEBUG = false;",
      "newText": "const PORT = 8080;\nconst DEBUG = true;"
    }
  ],
  "explanation": "Updated port to 8080 and enabled debug mode for development"
}
```

## 2. Multiple Sequential Edits
Edits are applied in order. Each edit sees the result of previous edits.

```json
{
  "filepath": "app.js",
  "edits": [
    {"oldText": "function init() {", "newText": "async function init() {"},
    {"oldText": "const data = fetch()", "newText": "const data = await fetch()"}
  ],
  "explanation": "Converted init function to async/await pattern for better error handling"
}
```

## 3. Replace All Occurrences

**Block/structure replacement** (oldText contains `\n`):
```json
{
  "filepath": "handlers.js",
  "edits": [
    {
      "oldText": "function handler() {\n  return false;\n}",
      "newText": "function handler() {\n  return true;\n}",
      "replaceAll": true  // Contains \n: replaces all matching blocks
    }
  ]
}
```

**Substring/token replacement** (oldText has NO `\n`):
```json
{
  "filepath": "legacy.js",
  "edits": [
    {
      "oldText": "var ",
      "newText": "let ",
      "replaceAll": true  // No \n: uses substring matching (max 1000)
    }
  ]
}
```

## 4. Insert at File Start
```json
{
  "filepath": "script.py",
  "edits": [
    {"oldText": "^", "newText": "#!/usr/bin/env python3\n"}
  ]
}
```

## 5. Insert at File End
```json
{
  "filepath": "config.js",
  "edits": [
    {"oldText": "$", "newText": "\nmodule.exports = config;"}
  ]
}
```

## 6. Delete Content
```json
{
  "filepath": "test.js",
  "edits": [
    {"oldText": "console.log('debug');\n", "newText": ""}
  ]
}
```

## 7. Initialize Empty File Contents
Use empty `oldText` to set initial contents for a new or empty file.
```json
{
  "filepath": "new_file.txt",
  "edits": [
    {"oldText": "", "newText": "initial content"}
  ]
}
```

## 8. Replace Entire File Contents
Use `overwrite` mode to replace all file contents completely.

```json
{
  "filepath": "config.json",
  "mode": "overwrite",
  "edits": [
    {"oldText": "", "newText": "{\"version\": \"2.0\"}"}
  ]
}
```

# Critical Rules for oldText

**oldText must match file content exactly:**
- ✓ Use proper JSON escaping (`\n` for newlines, `\"` for quotes, `\\` for backslashes)
- ✓ Include enough context (function names, unique variables) for unique matching
- ❌ Never include line numbers (e.g., "117: function test()")
- ❌ Never include editor artifacts (→, │, gutter symbols)
- ❌ Never use empty `{"oldText": "", "newText": ""}` to read or inspect files - this is invalid and does nothing.

**⚠️ WARNING: Avoid overlapping patterns when batching substring edits:**
**NEVER make multiple insert_edit_into_file calls that modify the same variables/text especially when doing replaceAll with substring matching.**
```json
// ❌ BAD - "util" matches inside "cc_diff_utils"
[
// First call renames variables
{"oldText": "local diff_utils", "newText": "local cc_diff_utils"}
// Second call tries to rename again - but "diff_utils" is now "cc_diff_utils"!
{"oldText": "diff_utils", "newText": "cc_diff_utils", "replaceAll": true}
// Result: "cc_cc_diff_utils" (double prefix!)
]

// ✓ GOOD - Use specific delimiters or context
[
  {"oldText": "local diff_utils", "newText": "local cc_diff_utils", "replaceAll": true},
  {"oldText": "local util ", "newText": "local cc_util ", "replaceAll": true}
]
```

# Best Practices

- **Always provide an `explanation` field** - Even simple changes benefit from brief context (e.g., "Fix typo in variable name", "Update API endpoint to v2")
- Edits are applied sequentially (each sees the result of previous edits)
- Use `replaceAll: true` when you want to change all occurrences
- For ambiguous matches, add more surrounding context to `oldText`
- When unsure about current file content, If available, use `read_file` first

# Troubleshooting

**"No confident matches found"** - `oldText` doesn't match file. If you have access to `read_file` tool, use it to verify exact content including whitespace.

**"Ambiguous matches"** - Add more unique context to `oldText`, or use `replaceAll: true` to change all occurrences.

**"Conflicting edits"** - Edits overlap same region. Combine into single edit.

**"Missing fields"** - Every edit needs both `oldText` and `newText`. Check JSON structure.
