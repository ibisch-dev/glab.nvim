-- Inline discussion-thread overlay on top of codediff.nvim's `:CodeDiff pr`
-- view.
--
-- UNVERIFIED ASSUMPTIONS — codediff.nvim was not available to test against in
-- the environment this file was first written in. Before relying on the mark
-- placement in `_place_marks_for_file`, run the spike described in the plan
-- (create-a-nvim-plugin-graceful-lagoon.md, "De-risking spike"):
--   1. Buffer naming: assumed that codediff's diff-pane buffer names, whatever
--      internal scheme they use, contain the repo-relative path as a
--      substring (checked via glab.util.path_matches). Confirm this against a
--      real `:CodeDiff pr <n>` session and fix `path_matches`/the matching
--      logic here if the real scheme doesn't satisfy it.
--   2. Window ordering: assumed the left-most window (lowest screen column)
--      in a 2-window side-by-side layout is the "old" side and the right-most
--      is "new", matching `diff.original_position = "left"` (codediff's
--      documented default). If the user's codediff config sets
--      `original_position = "right"` this is inverted — read that config value
--      instead of hardcoding "left is old" once confirmed.
--   3. Line-number correlation: assumed buffer line number == GitLab's
--      new_line/old_line with no filler-line offset. If side-by-side view
--      inserts blank filler lines to align hunks, this breaks both mark
--      placement (cosmetic) and new-thread creation from the cursor (posts to
--      the wrong line in GitLab — much worse). Confirm before trusting `gn`.
--
-- Until verified, `:Glab mr note list {iid}` (M.list_all) is the safe,
-- fully-independent fallback for reading/replying/resolving discussions.

local M = {}

local ns = vim.api.nvim_create_namespace("glab_discussions")

-- state.by_iid[iid] = {
--   discussions = { <raw discussion objects> },
--   by_path = { [path] = { new = { [line] = {disc,...} }, old = { [line] = {disc,...} } } },
-- }
local state = {
  by_iid = {},
  current_tabpage_iid = {}, -- [tabpage] = iid
  current_file = {}, -- [tabpage] = path
  marked_bufs = {}, -- [buf] = true
  watched_bufs = {}, -- [buf] = true
  buf_meta = {}, -- [buf] = { path = ..., side = "old"|"new" }
  group = nil,
}

local function note_of(discussion)
  return discussion.notes and discussion.notes[1]
end

local function is_resolved(discussion)
  local n = note_of(discussion)
  return n ~= nil and n.resolved == true
end

--- Fetch all diff-positioned discussions for `iid` and index them by path/line.
function M.fetch(iid, callback)
  require("glab.cli").run_json({ "mr", "note", "list", iid, "-t", "diff" }, {}, function(ok, discussions)
    if not ok then
      callback(false, discussions)
      return
    end

    local by_path = {}
    for _, disc in ipairs(discussions) do
      local n = note_of(disc)
      local pos = n and n.position
      if pos then
        local path = pos.new_path or pos.old_path
        if path then
          by_path[path] = by_path[path] or { new = {}, old = {} }
          if pos.new_line then
            by_path[path].new[pos.new_line] = by_path[path].new[pos.new_line] or {}
            table.insert(by_path[path].new[pos.new_line], disc)
          end
          if pos.old_line then
            by_path[path].old[pos.old_line] = by_path[path].old[pos.old_line] or {}
            table.insert(by_path[path].old[pos.old_line], disc)
          end
        end
      end
    end

    state.by_iid[iid] = { discussions = discussions, by_path = by_path }
    callback(true, discussions)
  end)
end

function M.refresh(iid)
  M.fetch(iid, function(ok)
    if not ok then
      return
    end
    for tabpage, tracked_iid in pairs(state.current_tabpage_iid) do
      if tracked_iid == iid and vim.api.nvim_tabpage_is_valid(tabpage) then
        local path = state.current_file[tabpage]
        if path then
          M._place_marks_for_file(tabpage, iid, path)
        end
      end
    end
  end)
end

local function clear_marks(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

local function set_mark(buf, line, discs)
  local cfg = require("glab.config").get().discussions
  local unresolved = false
  for _, d in ipairs(discs) do
    if not is_resolved(d) then
      unresolved = true
      break
    end
  end
  -- A note's line may not exist in this buffer yet: routinely because
  -- codediff names the buffer before finishing loading its content (expected
  -- — M._watch_for_content retries once real content lands), or, more rarely,
  -- because of a genuinely stale position / wrong line-correlation. Either
  -- way nvim_buf_set_extmark throws hard on an out-of-range line, and one bad
  -- line must not abort marking every other line in the file. The transient
  -- case is the common one, so this stays silent rather than logging noise on
  -- every buffer-load.
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, line - 1, 0, {
    sign_text = cfg.sign_text,
    sign_hl_group = unresolved and cfg.sign_hl or cfg.resolved_sign_hl,
    virt_text = cfg.virtual_text and { { " " .. #discs .. " comment(s)", "Comment" } } or nil,
    priority = 100,
  })
end

function M._ensure_keymaps(buf, iid)
  if state.marked_bufs[buf] then
    return
  end
  state.marked_bufs[buf] = true

  local cfg = require("glab.config").get().keymaps.discussion
  local opts = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set("n", cfg.toggle_thread, function()
    M._show_thread_at_cursor(buf, iid)
  end, opts)

  vim.keymap.set("n", cfg.new_thread, function()
    M._new_thread_at_cursor(buf, iid)
  end, opts)

  vim.keymap.set("n", cfg.next_thread, function()
    M._jump(buf, 1)
  end, opts)
  vim.keymap.set("n", cfg.prev_thread, function()
    M._jump(buf, -1)
  end, opts)
end

function M._jump(buf, dir)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  if #marks == 0 then
    return
  end
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  table.sort(marks, function(a, b)
    return a[2] < b[2]
  end)
  if dir > 0 then
    for _, m in ipairs(marks) do
      if m[2] + 1 > cur then
        vim.api.nvim_win_set_cursor(0, { m[2] + 1, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(0, { marks[1][2] + 1, 0 })
  else
    for i = #marks, 1, -1 do
      if marks[i][2] + 1 < cur then
        vim.api.nvim_win_set_cursor(0, { marks[i][2] + 1, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(0, { marks[#marks][2] + 1, 0 })
  end
end

local function discussions_at_cursor(buf)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { line - 1, 0 }, { line - 1, -1 }, {})
  local meta = state.buf_meta[buf]
  if #marks == 0 or not meta then
    return nil
  end
  local entry = state.by_iid[state.current_tabpage_iid[vim.api.nvim_get_current_tabpage()]]
  if not entry then
    return nil
  end
  local side = entry.by_path[meta.path] and entry.by_path[meta.path][meta.side]
  return side and side[line]
end

function M._show_thread_at_cursor(buf, iid)
  local discs = discussions_at_cursor(buf)
  if not discs or #discs == 0 then
    vim.notify("No discussion thread on this line", vim.log.levels.INFO)
    return
  end
  if #discs == 1 then
    M._open_float(discs[1], iid)
    return
  end
  vim.ui.select(discs, {
    prompt = "Threads on this line",
    format_item = function(d)
      local n = note_of(d)
      return string.format("[%s] %s", is_resolved(d) and "x" or " ", (n.body or ""):sub(1, 60))
    end,
  }, function(choice)
    if choice then
      M._open_float(choice, iid)
    end
  end)
end

function M._new_thread_at_cursor(buf, iid)
  local meta = state.buf_meta[buf]
  if not meta then
    vim.notify("glab.nvim: could not resolve this buffer to a known file — aborting", vim.log.levels.WARN)
    return
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]

  vim.ui.input({ prompt = "New comment: " }, function(text)
    if not text or text == "" then
      return
    end
    local cli_args = { "mr", "note", "create", iid, "-m", text, "--file", meta.path }
    if meta.side == "old" then
      vim.list_extend(cli_args, { "--old-line", tostring(line) })
    else
      vim.list_extend(cli_args, { "--line", tostring(line) })
    end
    require("glab.cli").run(cli_args, {}, function(ok, out)
      require("glab.util").notify_result(ok, out, "new comment")
      if ok then
        M.refresh(iid)
      end
    end)
  end)
end

local function render_thread_lines(discussion)
  local lines = {}
  for _, n in ipairs(discussion.notes or {}) do
    local author = n.author and (n.author.username or n.author.name) or "?"
    table.insert(lines, string.format("## %s  (%s)%s", author, n.created_at or "", n.resolved and "  [resolved]" or ""))
    table.insert(lines, "")
    vim.list_extend(lines, vim.split(n.body or "", "\n"))
    table.insert(lines, "")
  end
  table.insert(lines, "---")
  table.insert(lines, "[r]eply  [R]esolve/reopen  [q]uit")
  return lines
end

function M._open_float(discussion, iid)
  local util = require("glab.util")
  local lines = render_thread_lines(discussion)
  local buf = util.scratch_buf("glab://discussion/" .. tostring(discussion.id), "markdown")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.min(80, math.floor(vim.o.columns * 0.6))
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = math.max(width, 20),
    height = math.max(height, 3),
    style = "minimal",
    border = "rounded",
    title = " " .. tostring(discussion.id):sub(1, 8) .. " ",
  })

  local cfg = require("glab.config").get().keymaps.discussion
  local opts = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set("n", cfg.reply, function()
    vim.ui.input({ prompt = "Reply: " }, function(text)
      if not text or text == "" then
        return
      end
      require("glab.cli").run({ "mr", "note", "create", iid, "-m", text, "--reply", tostring(discussion.id) }, {}, function(ok, out)
        require("glab.util").notify_result(ok, out, "reply")
        if ok then
          M.refresh(iid)
          pcall(vim.api.nvim_win_close, win, true)
        end
      end)
    end)
  end, opts)

  vim.keymap.set("n", cfg.resolve, function()
    local verb = is_resolved(discussion) and "reopen" or "resolve"
    require("glab.cli").run({ "mr", "note", verb, iid, tostring(discussion.id) }, {}, function(ok, out)
      require("glab.util").notify_result(ok, out, "mr note " .. verb)
      if ok then
        M.refresh(iid)
        pcall(vim.api.nvim_win_close, win, true)
      end
    end)
  end, opts)

  vim.keymap.set("n", "q", function()
    pcall(vim.api.nvim_win_close, win, true)
  end, opts)
end

--- Fallback UI, independent of any codediff buffer discovery.
--- :Glab mr note list {iid} [glab-mr-note-list-flags...]
function M.list_all(iid, args)
  local cli_args = { "mr", "note", "list", iid }
  vim.list_extend(cli_args, args or {})

  require("glab.cli").run_json(cli_args, {}, function(ok, discs)
    if not ok then
      vim.notify("glab mr note list failed: " .. tostring(discs), vim.log.levels.ERROR)
      return
    end
    if #discs == 0 then
      vim.notify("No discussions found", vim.log.levels.INFO)
      return
    end
    vim.ui.select(discs, {
      prompt = "Discussions",
      format_item = function(d)
        local n = note_of(d)
        local pos = n and n.position
        local loc = pos and (pos.new_path or pos.old_path) or "general"
        return string.format("[%s] %s: %s", is_resolved(d) and "x" or " ", loc, (n and n.body or ""):sub(1, 60))
      end,
    }, function(choice)
      if choice then
        M._open_float(choice, iid)
      end
    end)
  end)
end

--- Thin CLI passthroughs, kept for parity with `glab`'s own grammar.
function M.create_passthrough(args)
  require("glab.cli").run(vim.list_extend({ "mr", "note", "create" }, args), {}, function(ok, out)
    require("glab.util").notify_result(ok, out, "mr note create")
  end)
end

function M.resolve_passthrough(args)
  require("glab.cli").run(vim.list_extend({ "mr", "note", "resolve" }, args), {}, function(ok, out)
    require("glab.util").notify_result(ok, out, "mr note resolve")
  end)
end

function M.reopen_passthrough(args)
  require("glab.cli").run(vim.list_extend({ "mr", "note", "reopen" }, args), {}, function(ok, out)
    require("glab.util").notify_result(ok, out, "mr note reopen")
  end)
end

--- Locate the (at most two) windows in `tabpage` whose buffer displays `path`,
--- and place marks for it. Authoritative path: driven by CodeDiffFileSelect,
--- which already tells us the real path, so matching only has to disambiguate
--- old vs. new among windows we already know contain this file.
function M._place_marks_for_file(tabpage, iid, path)
  local entry = state.by_iid[iid]
  local notes = entry and entry.by_path[path]
  if not notes then
    return
  end

  local util = require("glab.util")
  local wins = vim.tbl_filter(function(w)
    return util.path_matches(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)), path)
  end, vim.api.nvim_tabpage_list_wins(tabpage))

  if #wins == 0 then
    -- Degrade gracefully: leave discussions reachable via M.list_all instead
    -- of failing outright.
    return
  end

  table.sort(wins, function(a, b)
    return vim.api.nvim_win_get_position(a)[2] < vim.api.nvim_win_get_position(b)[2]
  end)

  for idx, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    -- See the UNVERIFIED ASSUMPTIONS note at the top of this file: left=old,
    -- right=new assumes codediff's default `original_position = "left"`.
    local side = (#wins == 1) and "new" or (idx == 1 and "old" or "new")

    clear_marks(buf)
    for line, discs in pairs(notes[side] or {}) do
      set_mark(buf, line, discs)
    end

    state.buf_meta[buf] = { path = path, side = side }
    M._ensure_keymaps(buf, iid)
    M._watch_for_content(buf, tabpage, iid, path)
  end
end

--- codediff.nvim creates each diff-pane buffer (with its final name) before
--- necessarily finishing populating its content, since that happens
--- asynchronously (fetching git blobs). A note's line may simply not exist
--- yet at the moment we first try to place it — set_mark's pcall stops that
--- from erroring, but without this, the mark would just never appear unless
--- something else happens to re-trigger placement later. Watch the buffer for
--- content changes and retry placement whenever it changes, so marks appear
--- as soon as the real content actually lands.
function M._watch_for_content(buf, tabpage, iid, path)
  if state.watched_bufs[buf] then
    return
  end
  state.watched_bufs[buf] = true
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_tabpage_is_valid(tabpage) then
          M._place_marks_for_file(tabpage, iid, path)
        end
      end)
      return false -- keep listening; content may load incrementally
    end,
  })
end

--- Best-effort placement across every currently-open pane in the tabpage,
--- used for CodeDiffOpen where the "first" file may already be showing before
--- any CodeDiffFileSelect has fired.
function M._place_all_marks(tabpage, iid)
  local entry = state.by_iid[iid]
  if not entry then
    return
  end
  for path, _ in pairs(entry.by_path) do
    M._place_marks_for_file(tabpage, iid, path)
  end
end

--- Called right after `:CodeDiff pr {iid}` is invoked.
function M.attach(iid)
  -- `:CodeDiff pr` opens the diff (and may fire CodeDiffOpen/CodeDiffFileSelect
  -- for its first file) synchronously, while our own `glab mr note list` call
  -- below is async. If codediff's event fires before this fetch returns,
  -- `state.by_iid[iid]` is still nil and placement for that first file is a
  -- silent no-op — nothing re-triggers it once the fetch *does* land, other
  -- than an unrelated refresh (e.g. adding a comment). Capture the tabpage
  -- now (assumed to already be the diff tab, since UI setup is synchronous
  -- even though data loading isn't) and redo placement once fetch completes,
  -- so a slow note-list fetch can't leave the first file unmarked.
  local tabpage = vim.api.nvim_get_current_tabpage()
  state.group = vim.api.nvim_create_augroup("GlabDiscussions", { clear = true })

  M.fetch(iid, function(ok, err)
    if not ok then
      vim.notify("glab.nvim: could not load discussions: " .. tostring(err), vim.log.levels.WARN)
      return
    end
    if vim.api.nvim_tabpage_is_valid(tabpage) then
      state.current_tabpage_iid[tabpage] = iid
      local path = state.current_file[tabpage]
      if path then
        M._place_marks_for_file(tabpage, iid, path)
      else
        M._place_all_marks(tabpage, iid)
      end
    end
  end)

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeDiffOpen",
    group = state.group,
    callback = function(ev)
      state.current_tabpage_iid[ev.data.tabpage] = iid
      M._place_all_marks(ev.data.tabpage, iid)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeDiffFileSelect",
    group = state.group,
    callback = function(ev)
      state.current_tabpage_iid[ev.data.tabpage] = iid
      state.current_file[ev.data.tabpage] = ev.data.path
      M._place_marks_for_file(ev.data.tabpage, iid, ev.data.path)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeDiffClose",
    group = state.group,
    callback = function(ev)
      state.current_tabpage_iid[ev.data.tabpage] = nil
      state.current_file[ev.data.tabpage] = nil
    end,
  })
end

return M
