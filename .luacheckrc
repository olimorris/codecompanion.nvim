max_comment_line_length = false
codes = true

exclude_files = {
  "tests/treesitter",
}

ignore = {
  "212", -- Unused argument
  "631", -- Line is too long
  "122", -- Setting a readonly global
  "542", -- Empty if branch
}

read_globals = {
  "vim",
  "a",
  "assert",
}
