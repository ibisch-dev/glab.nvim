local M = {}

--- Resolve the bare (no-iid) case to the current branch's MR iid, then call back.
local function resolve_iid(iid, callback)
  if iid ~= nil and iid ~= "" then
    callback(iid)
    return
  end
  require("glab.cli").run_json({ "mr", "view" }, {}, function(ok, mr)
    if not ok then
      vim.notify("Could not resolve current branch's MR: " .. tostring(mr), vim.log.levels.ERROR)
      return
    end
    callback(tostring(mr.iid))
  end)
end

function M._setup_keymaps(buf, iid)
  local cfg = require("glab.config").get().keymaps.view
  local opts = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set("n", cfg.diff, function()
    require("glab.mr.diff").open(iid, {})
  end, opts)
  vim.keymap.set("n", cfg.approve, function()
    require("glab.mr.actions").approve(iid, {})
  end, opts)
  vim.keymap.set("n", cfg.merge, function()
    require("glab.mr.actions").merge(iid, {})
  end, opts)
  vim.keymap.set("n", cfg.checkout, function()
    require("glab.mr.actions").checkout(iid, {})
  end, opts)
  vim.keymap.set("n", cfg.open_browser, function()
    require("glab.mr.actions").open_browser(iid)
  end, opts)
  vim.keymap.set("n", cfg.refresh, function()
    M.open(iid)
  end, opts)
  vim.keymap.set("n", cfg.close, "<cmd>bdelete<cr>", opts)
end

--- :Glab mr view [iid] [glab-mr-view-flags...]
function M.open(iid, args)
  resolve_iid(iid, function(resolved_iid)
    local cli_args = { "mr", "view", resolved_iid, "-c" }
    vim.list_extend(cli_args, args or {})

    require("glab.cli").run(cli_args, {}, function(ok, out)
      if not ok then
        vim.notify("glab mr view failed: " .. tostring(out), vim.log.levels.ERROR)
        return
      end

      local util = require("glab.util")
      local buf = util.scratch_buf("glab://mr/" .. resolved_iid, "markdown")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(util.strip_ansi(out), "\n"))
      vim.bo[buf].modifiable = false
      vim.api.nvim_set_current_buf(buf)
      M._setup_keymaps(buf, resolved_iid)
    end)
  end)
end

return M
