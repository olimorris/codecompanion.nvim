# Apply Patch Tool Specification

## Purpose
Implement the `apply_patch` tool for the `codecompanion` Neovim plugin (Lua) based on the `opencode` TypeScript implementation.

## Original Source Files
- `~/workspace/patch_tool/opencode/packages/opencode/src/tool/apply_patch.txt` - this is the prompt file that describes the tool and how to use it.
- `~/workspace/patch_tool/opencode/packages/opencode/src/tool/apply_patch.ts` - this is the logic we need to duplicate
- `~/workspace/patch_tool/opencode/packages/opencode/src/patch/index.ts` 

## codecompanion tool documentation
- https://codecompanion.olimorris.dev/extending/tools - documentation for implementing tools in codecompanion.

## Specification

### 1. Patch Format
The patch is enclosed in a high-level envelope:
```
*** Begin Patch
[ one or more file sections ]
*** End Patch
```

**File Section Headers**:
- `*** Add File: <path>`: Create a new file. Subsequent lines starting with `+` are the content.
- `*** Delete File: <path>`: Remove the specified file.
- `*** Update File: <path>`: Patch an existing file.
    - Optional: `*** Move to: <path>` immediately following the update header to rename the file.
    - Content updates are defined by "chunks" starting with `@@ <context>`.
    - Lines in chunks:
        - ` ` (space): Context line (must match original).
        - `-`: Line to remove.
        - `+`: Line to add.
    - Optional: `*** End of File` marker.

### 2. Core Logic & Behavior

**A. Parsing Phase**
- Strip heredoc wrappers if present.
- Identify `*** Begin Patch` and `*** End Patch` markers.
- Parse sections into "hunks" (Add, Delete, Update).
- For updates, capture the `change_context` and the sequences of `old_lines` and `new_lines`.

**B. Application Phase**
- **Add**: Create parent directories recursively and write the `+` prefixed content.
- **Delete**: Remove the file from the filesystem.
- **Update**:
    - **Seeking**: Locate the replacement point.
        1. Use `change_context` if provided to find the starting line.
        2. Match `old_lines` exactly.
        3. Fallback: Match after trimming trailing whitespace.
        4. Fallback: Match after trimming both ends.
        5. Fallback: Match after normalizing Unicode punctuation to ASCII.
    - **Replacement**: Replace the matched `old_lines` with `new_lines`.
    - **Rename**: If `*** Move to` is present, write the new content to the destination and delete the original.

**C. Verification & Constraints**
- Ensure paths are resolved relative to the project root.
- Validations:
    - Fail if `*** Begin/End Patch` markers are missing.
    - Fail if an `Update` hunk cannot find the expected `old_lines` or `context` in the target file.
    - Fail if a file to be updated or deleted does not exist.

### 3. Expected Input/Output
- **Input**: A string containing the full patch text.
- **Output**: A summary of changes (e.g., `A path/to/file`, `M path/to/file`, `D path/to/file`).

## Implementation Plan for CodeCompanion

### 1. Tool Structure
Define the tool in `lua/codecompanion/interactions/chat/tools/builtin/apply_patch.lua` using the `CodeCompanion.Tools.Tool` structure:
- **Name**: `apply_patch`
- **Description**: "Apply a structured patch to the codebase to add, delete, or update files."
- **Schema**: Full OpenAI compatible function schema.
    - `parameters`: Object with required `patchText` (string).
- **Opts**: `{ require_approval_before = true }` to ensure user safety during filesystem mutations.

### 2. Execution Logic (`cmds`)
Implement the core logic within a function in the `cmds` table. This function will receive `(self, args, opts)` and must return `{ status = "success"|"error", data = any }`.

**Internal Implementation Phases:**
- **Phase 1: The Parser (The "Frontend")**
    - Validate `*** Begin Patch` and `*** End Patch` markers.
    - Decompose `patchText` into a list of **Hunks** (Add, Delete, Update).
    - Parse chunks for updates (@@ markers, context, and +/- changes).
- **Phase 2: The Seeking Logic (The "Engine")**
    - Match `old_lines` using a fallback hierarchy:
        1. Exact Match $\rightarrow$ 2. RStrip Match $\rightarrow$ 3. Trim Match $\rightarrow$ 4. Normalized Match (Unicode $\rightarrow$ ASCII).
- **Phase 3: The Application Logic (The "Backend")**
    - Use `vim.fs.mkdir` (recursive) and `io.write` for **Add/Update**.
    - Use `vim.fs.remove` for **Delete**.
    - Handle **Rename** by writing to the new path and deleting the old one.
- **Phase 4: Summary Generation**
    - Return a success summary listing affected files with prefixes: `A` (Added), `M` (Modified/Moved), `D` (Deleted).

### 3. Output Handling (`output`)
- **`success`**: Use `meta.tools.chat:add_tool_output(self, stdout[1])` to share the summary with the LLM and user.
- **`error`**: Report the failure message back to the chat buffer.

### 4. Summary of Mapping

| TypeScript (`opencode`) | Lua (`codecompanion`) |
| :--- | :--- |
| `z.object({ patchText: ... })` | `schema.parameters.properties.patchText` |
| `Patch.parsePatch` | `cmds` function $\rightarrow$ internal `parse_patch` |
| `Patch.seekSequence` | `cmds` function $\rightarrow$ internal `seek_sequence` |
| `afs.writeWithDirs` | `vim.fs.mkdir` + `io.write` |
| `afs.remove` | `vim.fs.remove` |
| `Effect.fail` | `return { status = "error", data = "..." }` |
| `LSP.Diagnostic.report` | (Simplified) Summary of A/M/D files |


### 4. Advanced UX Extensions (Buffer Awareness & Visual Diff)

To align `apply_patch` with the user experience of `insert_edit_into_file`, the tool will be extended to support buffer-based editing and a visual review cycle.

#### A. Buffer-Aware Content Sourcing
- Implement a source abstraction similar to `insert_edit_into_file`:
    - `make_file_source`: Reads content from disk.
    - `make_buffer_source`: Reads content from an active Neovim buffer.
- When processing a patch hunk, check if the target path corresponds to an open buffer. If so, use the buffer as the source to ensure changes are applied to the current editor state.

#### B. Diff & Review Integration
- **Deferred Application**: Instead of applying changes immediately to disk/buffer, the tool will calculate the "Proposed State" for all affected files.
- **Visual Diff**: Integrate with `codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.diff` to:
    - Present a `minidiff` floating view showing the before/after state of the entire patch.
    - Use the `review` flow to allow the user to Accept, Reject, or View the changes.
- **Atomic Execution**: Only apply the actual writes (to buffer or disk) after the user approves the patch.

#### C. Refined Application Flow
1. **Parsing**: Parse `patchText` into hunks.
2. **Staging**: For each hunk:
    - Determine source (Buffer vs Disk).
    - Calculate new content based on seeking logic.
    - Store the `from_lines` and `to_lines`.
3. **Review**: Call `diff.review` with the aggregated changes.
4. **Commit**: On approval, execute the writes using the source's `write` method (updating buffers via `nvim_buf_set_lines` and files via `io.write`).



