local M = {}

local function build_cmd(args)
  local cfg = require("glab.config").get()
  local cmd = { cfg.glab_cmd }
  vim.list_extend(cmd, args)
  return cmd
end

--- Run `glab <args>` asynchronously.
--- callback(ok: boolean, stdout_or_message: string, raw: vim.SystemCompleted)
function M.run(args, opts, callback)
  opts = opts or {}
  vim.system(build_cmd(args), {
    text = true,
    cwd = opts.cwd or require("glab.util").git_root(),
    timeout = opts.timeout,
  }, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        local err = (obj.stderr ~= nil and obj.stderr ~= "") and obj.stderr or ("glab exited with code " .. obj.code)
        callback(false, err, obj)
      else
        callback(true, obj.stdout or "", obj)
      end
    end)
  end)
end

--- Same as `run`, but appends `-F json` and decodes stdout.
--- callback(ok: boolean, data_or_message: table|string, raw: vim.SystemCompleted|nil)
function M.run_json(args, opts, callback)
  local full = vim.deepcopy(args)
  vim.list_extend(full, { "-F", "json" })
  M.run(full, opts, function(ok, out, obj)
    if not ok then
      callback(false, out, obj)
      return
    end
    local decode_ok, decoded = pcall(vim.json.decode, out)
    if not decode_ok then
      callback(false, "failed to decode glab JSON output: " .. tostring(decoded), obj)
      return
    end
    callback(true, decoded, obj)
  end)
end

--- Blocking variant, for :checkhealth only.
function M.run_sync(args, opts)
  opts = opts or {}
  local obj = vim.system(build_cmd(args), { text = true, cwd = opts.cwd or require("glab.util").git_root() }):wait()
  if obj.code ~= 0 then
    return false, (obj.stderr ~= nil and obj.stderr ~= "") and obj.stderr or ("exit " .. obj.code)
  end
  return true, obj.stdout or ""
end

return M
