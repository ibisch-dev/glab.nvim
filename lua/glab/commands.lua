local M = {}

local subcommands = {
  mr = {
    list = function(args)
      require("glab.mr.list").run(args)
    end,
    view = function(args)
      require("glab.mr.view").open(args[1], vim.list_slice(args, 2))
    end,
    diff = function(args)
      require("glab.mr.diff").open(args[1], vim.list_slice(args, 2))
    end,
    approve = function(args)
      require("glab.mr.actions").approve(args[1], vim.list_slice(args, 2))
    end,
    merge = function(args)
      require("glab.mr.actions").merge(args[1], vim.list_slice(args, 2))
    end,
    checkout = function(args)
      require("glab.mr.actions").checkout(args[1], vim.list_slice(args, 2))
    end,
    close = function(args)
      require("glab.mr.actions").close(args[1])
    end,
    reopen = function(args)
      require("glab.mr.actions").reopen(args[1])
    end,
    note = {
      list = function(args)
        require("glab.mr.discussions").list_all(args[1], vim.list_slice(args, 2))
      end,
      create = function(args)
        require("glab.mr.discussions").create_passthrough(args)
      end,
      resolve = function(args)
        require("glab.mr.discussions").resolve_passthrough(args)
      end,
      reopen = function(args)
        require("glab.mr.discussions").reopen_passthrough(args)
      end,
    },
  },
}

function M.dispatch(opts)
  local fargs = opts.fargs
  local node, i = subcommands, 1
  while type(node) == "table" and fargs[i] ~= nil and node[fargs[i]] ~= nil do
    node = node[fargs[i]]
    i = i + 1
  end

  if type(node) ~= "function" then
    vim.notify("glab.nvim: unknown subcommand: " .. table.concat(fargs, " "), vim.log.levels.ERROR)
    return
  end

  node(vim.list_slice(fargs, i))
end

function M.complete(arglead, cmdline, _)
  local words = vim.split(cmdline, "%s+")
  -- words[1] is "Glab" itself; walk from words[2] onward through the tree.
  local node, depth = subcommands, 2
  while depth < #words and type(node) == "table" and node[words[depth]] ~= nil do
    node = node[words[depth]]
    depth = depth + 1
  end

  if type(node) ~= "table" then
    return {}
  end

  local candidates = vim.tbl_keys(node)
  table.sort(candidates)
  return vim.tbl_filter(function(c)
    return vim.startswith(c, arglead)
  end, candidates)
end

return M
