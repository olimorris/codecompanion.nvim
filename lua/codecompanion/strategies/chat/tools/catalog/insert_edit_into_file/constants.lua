---Constants for the insert_edit_into_file tool

local config = require("codecompanion.config")

local M = {}

---Get the file size limit from config or use default
---@return number The file size limit in bytes
local function get_file_size_limit()
  local opts = config.strategies.chat.tools["insert_edit_into_file"]
      and config.strategies.chat.tools["insert_edit_into_file"].opts
    or {}
  local limit_mb = opts.file_size_limit_mb or 2 -- Default 2MB
  return limit_mb * 1000000 -- Convert MB to bytes
end

---Size limits to prevent performance issues
M.LIMITS = {
  -- File and content size limits
  FILE_SIZE_MAX = get_file_size_limit(),
  SEARCH_TEXT_MAX = 50000, -- 50KB maximum search text size

  -- Line-based limits for different strategies
  CONTENT_LINES_STANDARD = 5000, -- Max lines for trimmed_lines strategy
  CONTENT_LINES_BLOCK_ANCHOR = 3000, -- Max lines for block_anchor (more intensive)
  SEARCH_LINES_STANDARD = 200, -- Max search lines for trimmed_lines
  SEARCH_LINES_BLOCK_ANCHOR = 100, -- Max search lines for block_anchor

  -- Iteration and matching limits
  ITERATIONS_MAX = 10000, -- Max iterations in trimmed_lines search
  ANCHOR_PAIRS_MAX = 50, -- Max anchor pairs to check in block_anchor
  SUBSTRING_MATCHES_MAX = 1000, -- Max substring replacements in replaceAll

  -- Performance thresholds
  STRATEGY_TIMEOUT_MS = 5000, -- Warning threshold for slow strategies (5 seconds)
}

---Confidence scores for different matching strategies
M.CONFIDENCE = {
  -- Strategy base confidence levels
  EXACT_MATCH = 1.0,
  SUBSTRING_EXACT_MATCH = 1.0,
  WHITESPACE_NORMALIZED = 0.95,
  PUNCTUATION_NORMALIZED = 0.93,
  POSITION_MARKERS = 1.0,
  TRIMMED_LINES_MIN = 0.8,
  BLOCK_ANCHOR_MIN = 0.6,

  -- Match selection thresholds
  AMBIGUITY_THRESHOLD = 0.15, -- Max confidence difference to consider matches ambiguous
  COMPARISON_EPSILON = 0.01, -- Epsilon for floating point confidence comparisons
  SIMILARITY_THRESHOLD_HIGH = 0.95, -- High similarity in trimmed_lines
  SIMILARITY_THRESHOLD_MEDIUM = 0.85, -- Medium similarity in trimmed_lines
  SIMILARITY_THRESHOLD_LOW = 0.7, -- Low similarity in trimmed_lines (minimum)
  BLOCK_ANCHOR_CONFIDENCE_MIN = 0.7, -- Minimum confidence for block_anchor matches
}

---Anchor detection settings
M.ANCHOR = {
  MEANINGFUL_LINE_MIN_LENGTH = 10, -- Minimum characters for a "meaningful" anchor line
}

return M
