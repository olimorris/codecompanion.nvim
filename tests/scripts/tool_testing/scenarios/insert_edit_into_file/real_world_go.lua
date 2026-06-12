-- A realistic Go retry package with tab indentation (~90 lines).
-- Model reads first, then makes three targeted changes.

local CONTENT = {
  "package retry",
  "",
  "import (",
  '\t"context"',
  '\t"errors"',
  '\t"fmt"',
  '\t"math"',
  '\t"time"',
  ")",
  "",
  "// Policy defines retry behaviour.",
  "type Policy struct {",
  "\tBaseDelay   time.Duration",
  "\tMaxAttempts int",
  "\tMaxDelay    time.Duration",
  "\tMultiplier  float64",
  "}",
  "",
  "// DefaultPolicy is a sensible starting point for most HTTP clients.",
  "var DefaultPolicy = Policy{",
  "\tBaseDelay:   200 * time.Millisecond,",
  "\tMaxAttempts: 3,",
  "\tMaxDelay:    5 * time.Second,",
  "\tMultiplier:  2.0,",
  "}",
  "",
  "// NonRetryable wraps an error to signal that no retry should be attempted.",
  "type NonRetryable struct {",
  "\tErr error",
  "}",
  "",
  "func (e *NonRetryable) Error() string { return e.Err.Error() }",
  "func (e *NonRetryable) Unwrap() error  { return e.Err }",
  "",
  "// IsNonRetryable reports whether err or any wrapped error is marked non-retryable.",
  "func IsNonRetryable(err error) bool {",
  "\tvar nr *NonRetryable",
  "\treturn errors.As(err, &nr)",
  "}",
  "",
  "// Do calls fn repeatedly until it succeeds, a non-retryable error is returned,",
  "// the context is cancelled, or the attempt limit is reached.",
  "func Do(ctx context.Context, policy Policy, fn func(ctx context.Context, attempt int) error) error {",
  "\tvar lastErr error",
  "\tfor attempt := 1; attempt <= policy.MaxAttempts; attempt++ {",
  "\t\tif err := ctx.Err(); err != nil {",
  '\t\t\treturn fmt.Errorf("context cancelled before attempt %d: %w", attempt, err)',
  "\t\t}",
  "\t\tlastErr = fn(ctx, attempt)",
  "\t\tif lastErr == nil {",
  "\t\t\treturn nil",
  "\t\t}",
  "\t\tif IsNonRetryable(lastErr) {",
  "\t\t\treturn lastErr",
  "\t\t}",
  "\t\tif attempt == policy.MaxAttempts {",
  "\t\t\tbreak",
  "\t\t}",
  "\t\tdelay := backoff(policy, attempt)",
  "\t\tselect {",
  "\t\tcase <-ctx.Done():",
  '\t\t\treturn fmt.Errorf("context cancelled during backoff: %w", ctx.Err())',
  "\t\tcase <-time.After(delay):",
  "\t\t}",
  "\t}",
  '\treturn fmt.Errorf("all %d attempts failed, last error: %w", policy.MaxAttempts, lastErr)',
  "}",
  "",
  "// backoff computes the delay before the next attempt using exponential backoff.",
  "func backoff(policy Policy, attempt int) time.Duration {",
  "\tdelay := float64(policy.BaseDelay) * math.Pow(policy.Multiplier, float64(attempt-1))",
  "\tif delay > float64(policy.MaxDelay) {",
  "\t\tdelay = float64(policy.MaxDelay)",
  "\t}",
  "\treturn time.Duration(delay)",
  "}",
}

local EXPECTED = {
  "package retry",
  "",
  "import (",
  '\t"context"',
  '\t"errors"',
  '\t"fmt"',
  '\t"math"',
  '\t"time"',
  ")",
  "",
  "// Policy defines retry behaviour.",
  "type Policy struct {",
  "\tBaseDelay   time.Duration",
  "\tMaxAttempts int",
  "\tMaxDelay    time.Duration",
  "\tMultiplier  float64",
  "}",
  "",
  "// DefaultPolicy is a sensible starting point for most HTTP clients.",
  "var DefaultPolicy = Policy{",
  "\tBaseDelay:   100 * time.Millisecond,",
  "\tMaxAttempts: 5,",
  "\tMaxDelay:    5 * time.Second,",
  "\tMultiplier:  2.0,",
  "}",
  "",
  "// NonRetryable wraps an error to signal that no retry should be attempted.",
  "type NonRetryable struct {",
  "\tErr error",
  "}",
  "",
  "func (e *NonRetryable) Error() string { return e.Err.Error() }",
  "func (e *NonRetryable) Unwrap() error  { return e.Err }",
  "",
  "// IsNonRetryable reports whether err or any wrapped error is marked non-retryable.",
  "func IsNonRetryable(err error) bool {",
  "\tvar nr *NonRetryable",
  "\treturn errors.As(err, &nr)",
  "}",
  "",
  "// Do calls fn repeatedly until it succeeds, a non-retryable error is returned,",
  "// the context is cancelled, or the attempt limit is reached.",
  "func Do(ctx context.Context, policy Policy, fn func(ctx context.Context, attempt int) error) error {",
  "\tvar lastErr error",
  "\tfor attempt := 1; attempt <= policy.MaxAttempts; attempt++ {",
  "\t\tif err := ctx.Err(); err != nil {",
  '\t\t\treturn fmt.Errorf("context cancelled before attempt %d: %w", attempt, err)',
  "\t\t}",
  "\t\tlastErr = fn(ctx, attempt)",
  "\t\tif lastErr == nil {",
  "\t\t\treturn nil",
  "\t\t}",
  "\t\tif IsNonRetryable(lastErr) {",
  "\t\t\treturn lastErr",
  "\t\t}",
  "\t\tif attempt == policy.MaxAttempts {",
  "\t\t\tbreak",
  "\t\t}",
  "\t\tdelay := backoff(policy, attempt)",
  "\t\tselect {",
  "\t\tcase <-ctx.Done():",
  '\t\t\treturn fmt.Errorf("context cancelled during backoff: %w", ctx.Err())',
  "\t\tcase <-time.After(delay):",
  "\t\t}",
  "\t}",
  '\treturn fmt.Errorf("failed after %d attempts: %w", policy.MaxAttempts, lastErr)',
  "}",
  "",
  "// backoff computes the delay before the next attempt using exponential backoff.",
  "func backoff(policy Policy, attempt int) time.Duration {",
  "\tdelay := float64(policy.BaseDelay) * math.Pow(policy.Multiplier, float64(attempt-1))",
  "\tif delay > float64(policy.MaxDelay) {",
  "\t\tdelay = float64(policy.MaxDelay)",
  "\t}",
  "\treturn time.Duration(delay)",
  "}",
}

return {
  cleanup = function(ctx)
    vim.fn.delete(ctx.test_file)
  end,

  description = "read_file + insert_edit_into_file: realistic Go package with tab indentation (~90 lines) — three changes after reading",
  name = "Real-world Go package",
  tools = { "read_file", "insert_edit_into_file" },
  tools_required = { "read_file", "insert_edit_into_file" },

  setup = function()
    local test_file = vim.fn.tempname() .. ".go"
    vim.fn.writefile(CONTENT, test_file)
    return { test_file = test_file }
  end,

  prompt = function(ctx)
    return string.format(
      [[First use @{read_file} to read `%s`, then use @{insert_edit_into_file} to make these three changes in a single tool call:

1. Change `BaseDelay` from `200 * time.Millisecond` to `100 * time.Millisecond`
2. Change `MaxAttempts` from `3` to `5`
3. Change the final error message from `"all %%d attempts failed, last error: %%w"` to `"failed after %%d attempts: %%w"`

The file uses real tab characters for indentation — your old_string must use real tabs. Read the file first. Do not ask for permission — call the tools directly.]],
      ctx.test_file
    )
  end,

  validate = function(ctx, run)
    local actual = vim.fn.readfile(ctx.test_file)
    if actual[#actual] == "" then
      actual[#actual] = nil
    end
    local file_ok = vim.deep_equal(actual, EXPECTED)
    local read_called = false
    for _, call in ipairs(run.tool_calls) do
      if call.name == "read_file" then
        read_called = true
        break
      end
    end
    return file_ok and read_called, {
      actual = table.concat(actual, "\n"),
      expected = table.concat(EXPECTED, "\n"),
      read_called = read_called,
    }
  end,
}
