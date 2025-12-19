return {
  diff = function(args)
    return vim.system({ "git", "diff", "--no-ext-diff", "--staged" }, { text = true }):wait().stdout
  end,
}
