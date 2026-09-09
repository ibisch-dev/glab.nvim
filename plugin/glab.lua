if vim.g.loaded_glab then
  return
end
vim.g.loaded_glab = true

vim.api.nvim_create_user_command("Glab", function(opts)
  require("glab.commands").dispatch(opts)
end, {
  nargs = "+",
  complete = function(arglead, cmdline, cursorpos)
    return require("glab.commands").complete(arglead, cmdline, cursorpos)
  end,
  desc = "GitLab CLI dispatcher (mirrors glab subcommand grammar)",
})
