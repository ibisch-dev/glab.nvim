local M = {}

local defaults = {
  glab_cmd = "glab",
  diff = {
    -- extra args forwarded verbatim onto `:CodeDiff pr {iid} ...`, e.g. { "--remote", "upstream" }
    codediff_extra_args = {},
  },
  discussions = {
    sign_text = "▌",
    sign_hl = "DiagnosticSignInfo",
    resolved_sign_hl = "DiagnosticSignOk",
    virtual_text = true,
  },
  keymaps = {
    view = {
      diff = "gd",
      approve = "ga",
      merge = "gM",
      checkout = "gco",
      open_browser = "gx",
      refresh = "gr",
      close = "q",
    },
    discussion = {
      toggle_thread = "gt",
      new_thread = "gn",
      reply = "r",
      resolve = "R",
      next_thread = "]t",
      prev_thread = "[t",
    },
  },
}

local state = nil

function M.setup(opts)
  state = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

function M.get()
  return state or vim.deepcopy(defaults)
end

return M
