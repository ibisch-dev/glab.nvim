local M = {}

local function do_open(iid, args)
  local cmd_parts = { "CodeDiff", "pr", iid }
  vim.list_extend(cmd_parts, require("glab.config").get().diff.codediff_extra_args)
  vim.list_extend(cmd_parts, args or {})
  -- NOTE: none of these values (iid, remote names, branch names) should ever
  -- contain spaces, so a naive space-joined :CodeDiff invocation is safe here.
  vim.cmd(table.concat(cmd_parts, " "))
  require("glab.mr.discussions").attach(iid)
end

--- :Glab mr diff [iid] [codediff-passthrough-flags...]
function M.open(iid, args)
  if iid ~= nil and iid ~= "" then
    do_open(iid, args)
    return
  end
  require("glab.cli").run_json({ "mr", "view" }, {}, function(ok, mr)
    if not ok then
      vim.notify("Could not resolve current branch's MR: " .. tostring(mr), vim.log.levels.ERROR)
      return
    end
    do_open(tostring(mr.iid), args)
  end)
end

return M
