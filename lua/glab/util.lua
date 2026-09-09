local M = {}

--- Walk upward from cwd looking for a `.git` entry.
function M.git_root()
  local found = vim.fs.find(".git", { upward = true, path = vim.loop.cwd() })[1]
  if not found then
    return vim.loop.cwd()
  end
  return vim.fs.dirname(found)
end

function M.strip_ansi(s)
  return (s:gsub("\27%[[0-9;]*m", ""))
end

--- Create a scratch buffer suitable for read-only plugin output.
function M.scratch_buf(name, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = filetype
  pcall(vim.api.nvim_buf_set_name, buf, name)
  return buf
end

--- Does `bufname` refer to `relpath`? codediff.nvim's diff-pane buffers are not
--- plain on-disk paths (no local checkout is made for `:CodeDiff pr`), so we
--- match by suffix on a path boundary rather than exact equality.
function M.path_matches(bufname, relpath)
  if bufname == "" or relpath == nil or relpath == "" then
    return false
  end
  if bufname == relpath then
    return true
  end
  if not vim.endswith(bufname, relpath) then
    return false
  end
  local prefix_len = #bufname - #relpath
  if prefix_len == 0 then
    return true
  end
  local boundary = bufname:sub(prefix_len, prefix_len)
  return boundary == "/" or boundary == ":" or boundary == "\\"
end

function M.notify_result(ok, out, verb)
  if ok then
    vim.notify(verb .. " succeeded", vim.log.levels.INFO)
  else
    vim.notify(verb .. " failed: " .. tostring(out), vim.log.levels.ERROR)
  end
end

return M
