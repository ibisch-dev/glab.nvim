local M = {}

local function run(args, verb)
  require("glab.cli").run(args, {}, function(ok, out)
    require("glab.util").notify_result(ok, out, verb)
  end)
end

function M.approve(iid, args)
  local cli_args = { "mr", "approve" }
  if iid ~= nil and iid ~= "" then
    table.insert(cli_args, iid)
  end
  vim.list_extend(cli_args, args or {})
  run(cli_args, "mr approve")
end

function M.checkout(iid, args)
  local cli_args = { "mr", "checkout" }
  if iid ~= nil and iid ~= "" then
    table.insert(cli_args, iid)
  end
  vim.list_extend(cli_args, args or {})
  run(cli_args, "mr checkout")
end

function M.close(iid)
  local cli_args = { "mr", "close" }
  if iid ~= nil and iid ~= "" then
    table.insert(cli_args, iid)
  end
  run(cli_args, "mr close")
end

function M.reopen(iid)
  local cli_args = { "mr", "reopen" }
  if iid ~= nil and iid ~= "" then
    table.insert(cli_args, iid)
  end
  run(cli_args, "mr reopen")
end

function M.open_browser(iid)
  local cli_args = { "mr", "view" }
  if iid ~= nil and iid ~= "" then
    table.insert(cli_args, iid)
  end
  table.insert(cli_args, "-w")
  require("glab.cli").run(cli_args, {}, function(ok, out)
    if not ok then
      vim.notify("glab mr view -w failed: " .. tostring(out), vim.log.levels.ERROR)
    end
  end)
end

--- `glab` gets no tty under vim.system, so an interactive merge would hang
--- forever waiting for confirmation it can never receive. Confirm here and
--- force --yes through instead.
function M.merge(iid, args)
  args = args or {}
  local has_yes = vim.tbl_contains(args, "--yes") or vim.tbl_contains(args, "-y")

  vim.ui.select({ "Yes", "No" }, {
    prompt = string.format("Merge MR %s?", iid ~= nil and iid ~= "" and ("!" .. iid) or "(current branch)"),
  }, function(choice)
    if choice ~= "Yes" then
      return
    end
    local cli_args = { "mr", "merge" }
    if iid ~= nil and iid ~= "" then
      table.insert(cli_args, iid)
    end
    vim.list_extend(cli_args, args)
    if not has_yes then
      table.insert(cli_args, "--yes")
    end
    run(cli_args, "mr merge")
  end)
end

return M
