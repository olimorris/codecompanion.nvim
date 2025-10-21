Use edit_tool_exp for safe, reliable file editing with advanced capabilities.

# Quick Reference – Basic Usage
```json
{
  "filepath": "path/to/file.js",
  "edits": [
    {
      "oldText": "function getName() {\n return this.name;\n}",
      "newText": "function getFullName() {\n return this.firstName + ' ' + this.lastName;\n}",
      "replaceAll": false
    }
  ],
  "dryRun": false,
  "mode": "append",
  "explanation": "Additional notes"
}
```

# CRITICAL SCHEMA REQUIREMENTS
**EVERY edit MUST have BOTH oldText AND newText - NO EXCEPTIONS**

Common mistakes that will cause FAILURE:
❌ Missing oldText field (required!)
❌ Missing newText field (required!)
❌ Putting "filepath" inside edits array (it goes at top level)
❌ Putting "explanation" inside edits array (it goes at top level)
❌ Making "edits" a string instead of an array
❌ Using single quotes instead of double quotes

Correct structure:
✓ filepath: at TOP LEVEL
✓ edits: ARRAY of objects at TOP LEVEL
✓ Each edit object: {"oldText": "...", "newText": "...", "replaceAll": false}
✓ explanation: at TOP LEVEL (optional)

# Parameters, Rules, and Best Practices
- **filepath**: Required. Top-level field. File to edit.
- **edits**: Required. Top-level ARRAY (not string). Each edit needs "oldText" AND "newText".
- **oldText**: REQUIRED in every edit. Exact text to find. Cannot be empty for normal edits.
- **newText**: REQUIRED in every edit. Replacement text. Can be empty for deletions.
- **replaceAll**: Optional. Set to true for global replacements (substring mode if no newlines).
- **dryRun**: Optional. Preview changes if true. Default false.
- **mode**: Optional. "append" (default) or "overwrite" (replace entire file).
- **explanation**: Optional. Top-level field. Description of changes.


## Edit Operations:

### Standard Replacement (Block/Line Matching):
{
  "oldText": "exact text to find",
  "newText": "replacement text",
  "replaceAll": false  // true to replace ALL occurrences
}

### Substring Replacement (Token/Pattern Matching):
When `replaceAll: true` and `oldText` contains NO newlines, the tool automatically uses substring matching for efficient token/keyword replacement:

{
  "oldText": "var ",
  "newText": "let ",
  "replaceAll": true
}

**Behavior:**
- Finds ALL plain-text occurrences of oldText within the file (no regex)
- Does NOT require full-line match - replaces within lines
- Perfect for: keyword changes (var→let), API renames (oldAPI.→newAPI.), token updates
- Limit: 1000 matches maximum for performance
- Must NOT contain newlines in oldText

**Examples:**
```
// Replace all var declarations with let
{ "oldText": "var ", "newText": "let ", "replaceAll": true }

// Update API namespace
{ "oldText": "oldNS.", "newText": "newNS.", "replaceAll": true }

// Remove trailing spaces
{ "oldText": "TODO: ", "newText": "DONE: ", "replaceAll": true }
```

**CRITICAL WARNING - Overlapping Patterns:**
When using multiple substring replacements, patterns can overlap and cause double replacements!

**Bad Example (WILL CAUSE BUGS):**
```
// DON'T DO THIS - 'util' will match inside 'cc_diff_utils'!
{ "oldText": "diff_utils", "newText": "cc_diff_utils", "replaceAll": true }
{ "oldText": "util", "newText": "cc_util", "replaceAll": true }
// Result: cc_diff_utils → cc_diff_cc_utils (WRONG!)
```

**Good Example (Use specific patterns):**
```
// DO THIS - Use word boundaries or delimiters
{ "oldText": "local diff_utils", "newText": "local cc_diff_utils", "replaceAll": true }
{ "oldText": "local util ", "newText": "local cc_util ", "replaceAll": true }
// Or combine into one edit with full context
```

**Rule:** If newText from Edit #1 contains oldText from Edit #2, you have overlapping patterns!
- Check: Does "cc_diff_utils" contain "util"? YES → Will cause double replacement
- Solution: Use more specific patterns that won't match the replaced text
- Alternative: Make separate edit_tool_exp calls for each rename instead of batching

**NOT for substring mode:**
- Multi-line text (use block matching instead)
- Structural changes (functions, classes)
- When you need indentation/whitespace context
- Overlapping patterns (causes double replacements)

### File Boundary Operations:
- **Start of file**: Use oldText: "^" or "<<START>>"
- **End of file**: Use oldText: "$" or "<<END>>"
- **Replacement pattern**: oldText: "first line", newText: "new content\nfirst line"

### Empty Files:
{
  "oldText": "",  // Empty oldText for empty files
  "newText": "initial content"
}

### Deletion:
{
  "oldText": "text to remove",
  "newText": ""  // Empty newText deletes content
}

### Complete File Replacement:
{
  "mode": "overwrite",
  "edits": [{ "oldText": "", "newText": "entire new file content" }]
}

## Smart Matching Features:
- **Exact matching**: Tries exact text first
- **Substring matching**: For replaceAll with single-line patterns (automatic)
- **Whitespace tolerance**: Handles spacing/indentation differences
- **Newline variants**: Works with/without trailing newlines (fixes echo "text" > file issues)
- **Block anchoring**: Uses first/last lines for context
- **Adaptive ambiguity resolution**: If matches are too similar, tries next strategy automatically
- **Conflict detection**: Prevents overlapping edits

**CRITICAL JSON REQUIREMENTS - TOOL WILL FAIL IF NOT FOLLOWED**:
- Use double quotes (") ONLY - never single quotes (')
- "edits" MUST be a JSON array [ ] - NEVER a string
- Boolean values: true/false (not "True"/"False" or "true"/"false")
- NO string wrapping of JSON objects or arrays
- NO double-escaping of quotes or backslashes

### Correct Format:
{
  "filepath": "path/to/file.js",
  "edits": [
    {
      "oldText": "function getName() {\n  return this.name;\n}",
      "newText": "function getFullName() {\n  return this.firstName + ' ' + this.lastName;\n}"
    }
  ],
  "dryRun": false
}

### Incorrect Format (will cause errors):
{
  "filepath": "path/to/file.js",
  "edits": "[{'oldText': 'function getName()', 'newText': 'function getFullName()'}]",  // Wrong: edits as string
  "dryRun": "false"  // Wrong: boolean as string
}

## oldText Format Rules:
**Critical**: oldText must match file content exactly
- **Never include line numbers** (like "117:", "118:") in oldText
- **Use actual text content only**, exactly as it appears in the file
- **Match exact quotes and escaping** - use "" not \"\"
- **Copy text directly** from file content, don't add line prefixes
- **No editor artifacts** - exclude gutters, line numbers, syntax highlighting markers

### Wrong Examples:
 "oldText": "117:  local cwd_icon = \"\""  // Line numbers included
 "oldText": "→   function test()"        // Tab/space indicators included
 "oldText": "│ return value"            // Editor gutter characters included
 "oldText": "local name = \\\"John\\\""  // Double-escaped quotes

### Correct Examples:
 "oldText": "local cwd_icon = \"\""      // Clean, actual file content
 "oldText": "function test()"           // No editor artifacts
 "oldText": "return value"              // Pure code content
 "oldText": "local name = \"John\""     // Proper escaping

## Best Practices:
 **Be specific**: Include enough context (function names, unique variables)
 **Use exact formatting**: Match spaces, tabs, indentation exactly
 **Start with dryRun: false**: for testing the tool, always set dryRun to false unless the user explicitly requests a dry run
 **Sequential edits**: Each edit assumes previous ones completed
 **Handle edge cases**: Empty files, boundary insertions, deletions

## Error Recovery:
- System provides helpful error messages with suggestions
- Handles malformed input gracefully
- Detects ambiguous matches and requests clarification
- Suggests adding more context for unique identification

## Examples:

### Multiple Sequential Edits:
{
  "filepath": "config.js",
  "edits": [
    { "oldText": "const PORT = 3000", "newText": "const PORT = 8080" },
    { "oldText": "DEBUG = false", "newText": "DEBUG = true" }
  ]
}

### Substring Replacement Across File:
{
  "filepath": "src/app.js",
  "edits": [
    { "oldText": "var ", "newText": "let ", "replaceAll": true }
  ]
}

### Add to File Start:
{
  "filepath": "script.py",
  "edits": [{ "oldText": "^", "newText": "#!/usr/bin/env python3\n" }]
}

### Block Replace All (Multi-line):
{
  "filepath": "legacy.js",
  "edits": [{
    "oldText": "function oldHandler() {\n  return false;\n}",
    "newText": "function oldHandler() {\n  return true;\n}",
    "replaceAll": true
  }]
}

## Common Issues & Solutions:

 **"No confident matches found"**
- Check formatting: spaces, tabs, newlines must match exactly
- Add more context: include function names, surrounding lines
- For files without trailing newlines (like echo "text" > file): try both variants

 **"Line numbers in oldText"**
- **Problem**: Including line numbers like "117:  local function test()"
- **Solution**: Use only the actual code content: "local function test()"
- **Remember**: oldText should match file content exactly, not what you see in editors with line numbers

 **"Ambiguous matches found"**
- **NEW BEHAVIOR**: When matches are too similar, the tool tries the next matching strategy automatically for better disambiguation
- **For substring replacement**: Use replaceAll: true to replace ALL occurrences at once
- **For targeted edits**: Include more surrounding context in oldText to make it unique

**Example - Multiple identical function definitions:**
```
// Strategy 1 finds multiple similar matches → tries strategy 2 automatically
// Strategy 2 (block anchor) might find unique match using context

// To edit ALL occurrences at once:
{ "oldText": "function process() {", "newText": "function process() {\n  // updated", "replaceAll": true }

// To edit a specific occurrence, add unique context:
{ "oldText": "class DataHandler {\n  function process() {", "newText": "class DataHandler {\n  function process() {\n    // updated specific one" }
```

**Example - Fixing Line Number Issues:**
```
 Wrong (includes line numbers):
{
  "oldText": "117:  -- Function to get the current working directory name\n118:  ---@return string\n119:  local function get_cwd()"
}

 Correct (actual file content only):
{
  "oldText": "-- Function to get the current working directory name\n---@return string\nlocal function get_cwd()"
}
```

 **"Conflicting edits"**
- Multiple edits target overlapping text
- Combine overlapping edits into a single operation
- Ensure edits are sequential and non-overlapping

 **Working with different file types:**
- Empty files: Use oldText: "" for first content
- Files from echo/printf: System handles missing newlines automatically
- Large files: Performance optimized with size limits
- Unicode content: Full UTF-8 support

 **When to use each approach:**
- Use position markers (^/$) when you don't know file content
- Use replacement patterns when you know the first/last lines
- Use overwrite mode for complete file replacement
- Use replaceAll for global find/replace operations

The system is extremely robust and handles whitespace differences, newline variations, and provides intelligent error messages when matches are ambiguous.