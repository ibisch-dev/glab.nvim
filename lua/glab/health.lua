local M = {}

function M.check()
  local health = vim.health

  health.start("glab.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10 (vim.system available)")
  else
    health.error("Neovim 0.10+ is required (uses vim.system)")
  end

  local cfg = require("glab.config").get()
  local glab_path = vim.fn.exepath(cfg.glab_cmd)
  if glab_path == "" then
    health.error("glab CLI not found on $PATH", { "Install: https://gitlab.com/gitlab-org/cli" })
  else
    health.ok("glab found: " .. glab_path)
    -- `glab auth status` writes its human-readable summary to stderr even on
    -- success; only the exit code is authoritative. Verify this assumption
    -- against your installed glab version and adjust if it differs.
    local ok, out = require("glab.cli").run_sync({ "auth", "status" })
    if ok then
      health.ok("glab auth status: OK")
    else
      health.warn("glab auth status failed: " .. out, { "Run `glab auth login`" })
    end
  end

  local codediff_ok = pcall(require, "codediff")
  if codediff_ok then
    health.ok("codediff.nvim found")
  else
    health.error("codediff.nvim not found (required for `:Glab mr diff`)", {
      "Install esmuellert/codediff.nvim",
    })
  end

  if vim.fs.find(".git", { upward = true, path = vim.loop.cwd() })[1] then
    health.ok("Inside a git repository")
  else
    health.warn("Not inside a git repository — glab needs repo context to resolve merge requests")
  end
end

return M
