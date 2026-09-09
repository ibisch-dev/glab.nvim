local M = {}

--- :Glab mr list [glab-mr-list-flags...]
function M.run(args)
  local cli_args = { "mr", "list" }
  vim.list_extend(cli_args, args or {})

  require("glab.cli").run_json(cli_args, {}, function(ok, result)
    if not ok then
      vim.notify("glab mr list failed: " .. tostring(result), vim.log.levels.ERROR)
      return
    end
    if #result == 0 then
      vim.notify("No merge requests found", vim.log.levels.INFO)
      return
    end

    vim.ui.select(result, {
      prompt = "Merge Requests",
      format_item = function(mr)
        local author = mr.author and mr.author.username or "?"
        return string.format("!%d %s (%s -> %s) [%s]", mr.iid, mr.title, mr.source_branch, mr.target_branch, author)
      end,
    }, function(choice)
      if choice then
        require("glab.mr.view").open(tostring(choice.iid))
      end
    end)
  end)
end

return M
