-- pointman.view: a review in Neovim, as neo-reviewr lays one out: the files and the agent's rounds on the left, the
-- diff on the right, each conversation drawn under its last line and each round as a bar under the comment it answers
-- (the same letters as the Pointman review pane). Everything shown comes from the node's review, so Neovim and the
-- pane show the same one; the keys call the extension's verbs, and their answer is the review again.

local api = require("pointman.api")
local diff = require("pointman.diff")
local store = require("pointman.store")

local M = {}

local NS = vim.api.nvim_create_namespace("pointman_view")
local TREE_NS = vim.api.nvim_create_namespace("pointman_tree")

local V = {} -- the open view: one at a time

local STATUS = { added = "+", modified = "~", removed = "-", deleted = "-", renamed = "»", copied = "»" }
local KIND = { add = "PointmanDiffAdd", del = "PointmanDiffDel", hunk = "PointmanDiffHunk", meta = "PointmanDim" }

local function cfg()
  return require("pointman").config
end

local function notify(msg, level)
  vim.notify("[pointman] " .. msg, level or vim.log.levels.INFO)
end

function M.hl()
  local function link(name, to)
    vim.api.nvim_set_hl(0, name, { link = to, default = true })
  end
  -- added and removed lines keep the language's colours: only a background, from the theme's DiffAdd and DiffDelete
  local function bg(name, src, gui, cterm)
    local h = vim.api.nvim_get_hl(0, { name = src, link = false }) or {}
    vim.api.nvim_set_hl(0, name, { bg = h.bg or gui, ctermbg = h.ctermbg or cterm, default = true })
  end
  bg("PointmanDiffAdd", "DiffAdd", "#20303b", 22)
  bg("PointmanDiffDel", "DiffDelete", "#3a2020", 52)
  link("PointmanDiffHunk", "DiffChange")
  link("PointmanDim", "Comment")
  link("PointmanTitle", "Title")
  link("PointmanYou", "Identifier")
  link("PointmanAgent", "Special")
  link("PointmanWaiting", "WarningMsg")
  link("PointmanResolved", "DiagnosticOk")
  link("PointmanRound", "DiagnosticInfo")
  link("PointmanRejected", "DiagnosticError")
end

function M.is_open()
  return V.diff_win ~= nil and vim.api.nvim_win_is_valid(V.diff_win) and V.tree_win ~= nil
    and vim.api.nvim_win_is_valid(V.tree_win)
end

function M.review()
  return V.id and store.reviews[V.id]
end

-- ── what's shown ────────────────────────────────────────────────────────────

local function round_counts(r)
  local a, d = 0, 0
  for _, f in ipairs(r.files or {}) do
    a, d = a + (f.additions or 0), d + (f.deletions or 0)
  end
  return a, d
end

local function source_words(r)
  local s = r.source or {}
  local who = ({ repo = "your repo", agent = "agent's copy", pr = "PR" })[s.kind] or (s.kind or "")
  if s.kind == "pr" and s.pr then
    who = "PR " .. (tostring(s.pr):match("(%d+)$") or s.pr)
  end
  local parts = { who, (s.base or "?") .. "…" .. (s.head or "HEAD") }
  if s.uncommitted then
    parts[#parts + 1] = "uncommitted too"
  end
  return table.concat(parts, " · ")
end

--- The files the diff window shows: the selected file, or the selected round's own files.
local function shown_files(r)
  if V.sel and V.sel.kind == "round" then
    for _, rd in ipairs(r.rounds or {}) do
      if rd.id == V.sel.id then
        return rd.files or {}, rd
      end
    end
  end
  local f = (r.files or {})[V.sel and V.sel.index or 1]
  return f and { f } or {}
end

-- ── the tree ────────────────────────────────────────────────────────────────

local function render_tree(r)
  local lines, marks = {}, {}
  V.rows = {}
  local function add(text, group, what)
    lines[#lines + 1] = text
    if group then
      marks[#marks + 1] = { #lines - 1, group }
    end
    if what then
      V.rows[#lines] = what
    end
  end
  add(" " .. (r.title or r.id), "PointmanTitle")
  add("  " .. source_words(r), "PointmanDim")
  local where = "  #" .. tostring(r.channel or "?") .. (r.agent and (" · @" .. r.agent) or "")
  if (r.waiting or 0) > 0 then
    where = where .. " · " .. r.waiting .. " to send (s)"
  end
  add(where, (r.waiting or 0) > 0 and "PointmanWaiting" or "PointmanDim")
  if r.state == "closed" then
    add("  closed", "PointmanDim")
  end
  add("")
  add("  FILES", "PointmanDim")
  for i, f in ipairs(r.files or {}) do
    local mark = (V.sel and V.sel.kind == "file" and V.sel.index == i) and "▸" or " "
    add(string.format(" %s%s %s  +%d −%d", mark, STATUS[f.status] or "?", f.path, f.additions or 0, f.deletions or 0),
      nil, { kind = "file", index = i })
  end
  if #(r.files or {}) == 0 then
    add("   (no changes)", "PointmanDim")
  end
  if #(r.rounds or {}) > 0 then
    add("")
    add("  ROUNDS", "PointmanDim")
    for _, rd in ipairs(r.rounds) do
      local a, d = round_counts(rd)
      local mark = (V.sel and V.sel.kind == "round" and V.sel.id == rd.id) and "▸" or " "
      local state = rd.state == "accepted" and "✓ accepted" or rd.state == "rejected" and "✗ rejected" or "proposed"
      local group = rd.state == "proposed" and "PointmanRound" or rd.state == "rejected" and "PointmanRejected"
        or "PointmanResolved"
      add(string.format(" %s Round %d · @%s · +%d −%d · %s", mark, rd.n or 0, rd.by or "?", a, d, state), group,
        { kind = "round", id = rd.id })
    end
  end
  local outdated = 0
  for _, c in ipairs(r.comments or {}) do
    if c.outdated then
      outdated = outdated + 1
    end
  end
  if outdated > 0 then
    add("")
    add(string.format("  %d outdated conversation%s", outdated, outdated > 1 and "s" or ""), "PointmanDim")
  end
  add("")
  add("  g? keys · q close", "PointmanDim")
  vim.bo[V.tree_buf].modifiable = true
  vim.api.nvim_buf_set_lines(V.tree_buf, 0, -1, false, lines)
  vim.bo[V.tree_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(V.tree_buf, TREE_NS, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, V.tree_buf, TREE_NS, m[1], 0, { line_hl_group = m[2] })
  end
end

-- ── conversations and rounds under the lines ────────────────────────────────

local function wrap(text, width)
  local out = {}
  for _, para in ipairs(vim.split(text or "", "\n", { plain = true })) do
    local line = ""
    for word in para:gmatch("%S+") do
      if line ~= "" and vim.fn.strdisplaywidth(line .. " " .. word) > width then
        out[#out + 1] = line
        line = word
      else
        line = line == "" and word or (line .. " " .. word)
      end
    end
    out[#out + 1] = line
  end
  return out
end

--- A conversation's events: the comment, then its replies oldest first, as the pane draws them.
local function events(c)
  local out = { { id = c.id, who = c.by, body = c.body, state = c.state } }
  for _, rp in ipairs(c.replies or {}) do
    out[#out + 1] = { id = rp.id, who = rp.by, body = rp.body, state = rp.state }
  end
  return out
end

local function who_hl(r, who)
  return who == r.by and "PointmanYou" or "PointmanAgent"
end

--- The virtual lines for a conversation: folded, its newest event on one line; open, every event in full.
local function thread_lines(r, c, width)
  local evs = events(c)
  local bar = c.state == "resolved" and "PointmanResolved" or c.outdated and "PointmanDim" or "PointmanRound"
  local tags = {}
  if c.outdated then
    tags[#tags + 1] = "outdated"
  end
  if c.state == "resolved" then
    tags[#tags + 1] = "✓ resolved"
  end
  local waiting = 0
  for _, e in ipairs(evs) do
    if e.state == "pending" then
      waiting = waiting + 1
    end
  end
  if waiting > 0 then
    tags[#tags + 1] = waiting .. " waiting"
  end
  local tag = #tags > 0 and (" · " .. table.concat(tags, " · ")) or ""
  if not V.open[c.id] then
    local last = evs[#evs]
    local first = wrap(last.body, 10000)[1] or ""
    local count = #evs > 1 and (" (" .. #evs .. ")") or ""
    -- the line fits the window: what's left after the mark, who, and the count and tags
    local room = width - 4 - vim.fn.strdisplaywidth((last.who or "?") .. ": " .. count .. tag)
    if vim.fn.strdisplaywidth(first) > math.max(10, room) then
      first = vim.fn.strcharpart(first, 0, math.max(10, room) - 1) .. "…"
    end
    return { {
      { "  ▸ ", bar },
      { (last.who or "?") .. ": ", who_hl(r, last.who) },
      { first, c.outdated and "PointmanDim" or "Normal" },
      { count .. tag, "PointmanDim" },
    } }
  end
  local out = { { { "  ┏ " .. c.id .. tag, bar } } }
  for _, e in ipairs(evs) do
    -- each line fits the window after the bar and the speaker's name, which the lines below it are indented by
    local body = wrap(e.body, math.max(20, width - 4 - vim.fn.strdisplaywidth((e.who or "?") .. ": ")))
    for i, l in ipairs(body) do
      local line = { { "  ┃ ", bar } }
      if i == 1 then
        line[#line + 1] = { (e.who or "?") .. ": ", who_hl(r, e.who) }
      else
        line[#line + 1] = { string.rep(" ", vim.fn.strdisplaywidth((e.who or "?") .. ": ")), "Normal" }
      end
      line[#line + 1] = { l, "Normal" }
      if i == #body and e.state == "pending" then
        line[#line + 1] = { " · waiting", "PointmanWaiting" }
      end
      out[#out + 1] = line
    end
  end
  out[#out + 1] = { { "  ┗ r reply · i edit · d discard · R resolve · ↩ fold", "PointmanDim" } }
  return out
end

local function round_line(rd)
  local a, d = round_counts(rd)
  local head = string.format("  ━━ Round %d · @%s · +%d −%d", rd.n or 0, rd.by or "?", a, d)
  if rd.state == "accepted" then
    return { { head .. " · ✓ accepted" .. (rd.verdict == "pending" and " (s sends it)" or ""), "PointmanResolved" } }
  elseif rd.state == "rejected" then
    local why = rd.reason and (": " .. rd.reason) or ""
    return { { head .. " · ✗ rejected" .. why .. (rd.verdict == "pending" and " (s sends it)" or ""),
      "PointmanRejected" } }
  end
  return { { head .. " · proposed", "PointmanRound" }, { "   a accept · x reject · ↩ its diff", "PointmanDim" } }
end

-- ── the diff ────────────────────────────────────────────────────────────────

function _G.pointman_statuscol()
  local m = V.map and V.map[vim.v.lnum]
  local n = m and (m.new or m.old)
  local w = V.gutter or 4
  if not n or vim.v.virtnum ~= 0 then
    return string.rep(" ", w)
  end
  local s = tostring(n)
  return string.rep(" ", math.max(0, w - #s)) .. s
end

local function render_diff(r)
  local files, round = shown_files(r)
  local lines, map = {}, {}
  for _, f in ipairs(files) do
    if #files > 1 or round then
      lines[#lines + 1] = "▌ " .. f.path .. (round and ("  (round " .. (round.n or "?") .. ")") or "")
      map[#map + 1] = { kind = "meta", path = f.path }
    end
    local fl, fm = diff.parse(f.patch)
    for i, l in ipairs(fl) do
      lines[#lines + 1] = l
      fm[i].path = f.path
      map[#map + 1] = fm[i]
    end
  end
  if #lines == 0 then
    lines, map = { "(nothing to show)" }, { { kind = "meta" } }
  end
  V.lines, V.map = lines, map
  local maxn = 0
  for _, m in ipairs(map) do
    maxn = math.max(maxn, m.new or 0, m.old or 0)
  end
  V.gutter = math.max(4, #tostring(maxn))
  vim.bo[V.diff_buf].modifiable = true
  vim.api.nvim_buf_set_lines(V.diff_buf, 0, -1, false, lines)
  vim.bo[V.diff_buf].modifiable = false
  local ft = #files == 1 and (vim.filetype.match({ filename = files[1].path }) or "") or ""
  if vim.bo[V.diff_buf].filetype ~= ft then
    vim.bo[V.diff_buf].filetype = ft
  end
  vim.api.nvim_buf_clear_namespace(V.diff_buf, NS, 0, -1)
  for i, m in ipairs(map) do
    if KIND[m.kind] then
      pcall(vim.api.nvim_buf_set_extmark, V.diff_buf, NS, i - 1, 0, { line_hl_group = KIND[m.kind] })
    end
  end
  if vim.api.nvim_win_is_valid(V.diff_win) then
    local title = round and ("Round " .. (round.n or "?") .. " · @" .. (round.by or "?")) or (files[1] and files[1].path)
    vim.wo[V.diff_win].winbar = "%#PointmanTitle# " .. (title or ""):gsub("%%", "%%%%")
  end

  -- where each conversation and round goes
  -- virtual lines start after the line numbers' column
  local width = vim.api.nvim_win_is_valid(V.diff_win) and vim.api.nvim_win_get_width(V.diff_win) - V.gutter - 2 or 78
  V.threads_at, V.rounds_at, V.thread_rows = {}, {}, {}
  local function row_in(path, side, line)
    for i, m in ipairs(map) do
      if m.path == path and ((side == "old" and m.old == line and m.kind ~= "add")
          or (side ~= "old" and m.new == line and m.kind ~= "del")) then
        return i
      end
    end
  end
  local placed = {}
  for _, c in ipairs(r.comments or {}) do
    local last = row_in(c.path, c.side, c["end"] or c.line)
    if last then
      local first = row_in(c.path, c.side, c.line) or last
      for i = math.min(first, last), math.max(first, last) do
        V.threads_at[i] = c
      end
      V.thread_rows[#V.thread_rows + 1] = last
      placed[c.id] = last
      pcall(vim.api.nvim_buf_set_extmark, V.diff_buf, NS, last - 1, 0,
        { virt_lines = thread_lines(r, c, width), priority = 200 })
    end
  end
  table.sort(V.thread_rows)
  for _, rd in ipairs(r.rounds or {}) do
    local row
    for _, cid in ipairs(rd.answers or {}) do
      row = row or placed[cid]
    end
    if row then
      V.rounds_at[row] = rd
      pcall(vim.api.nvim_buf_set_extmark, V.diff_buf, NS, row - 1, 0,
        { virt_lines = { round_line(rd) }, priority = 100 })
    elseif not round then
      -- answers no comment shown here: above the first line of a file it changes
      for _, f in ipairs(rd.files or {}) do
        if files[1] and f.path == files[1].path then
          V.rounds_at[1] = V.rounds_at[1] or rd
          pcall(vim.api.nvim_buf_set_extmark, V.diff_buf, NS, 0, 0,
            { virt_lines = { round_line(rd) }, virt_lines_above = true, priority = 100 })
          break
        end
      end
    end
  end
end

local function render()
  local r = M.review()
  if not (r and M.is_open()) then
    return
  end
  local view = vim.api.nvim_win_call(V.diff_win, vim.fn.winsaveview)
  render_tree(r)
  render_diff(r)
  pcall(vim.api.nvim_win_call, V.diff_win, function()
    vim.fn.winrestview(view)
  end)
end
M.render = render

-- ── doing things ────────────────────────────────────────────────────────────

--- Calls `review.<verb>` for the open review and keeps the review it answers with.
local function act(verb, params, done)
  local r = M.review()
  if not r then
    return
  end
  params = params or {}
  params.review = r.id
  api.call(verb, params, function(res, err)
    if res and res.review then
      store.put(res.review)
    end
    if err then
      if err.code == "stale" then
        store.refresh(r.id)
      end
      notify(err.message or "it failed", vim.log.levels.WARN)
    end
    if done then
      done(res, err)
    end
  end)
end
M.act = act

local function cursor_row()
  return vim.api.nvim_win_get_cursor(V.diff_win)[1]
end

local function thread_here()
  return V.threads_at and V.threads_at[cursor_row()]
end

--- The pending comment or reply of a conversation: the newest one waiting.
local function pending_in(c)
  local evs = events(c)
  for i = #evs, 1, -1 do
    if evs[i].state == "pending" then
      return evs[i]
    end
  end
end

local function ask(prompt, default, fn)
  vim.ui.input({ prompt = prompt, default = default }, function(text)
    if text and vim.trim(text) ~= "" then
      fn(text)
    end
  end)
end

function M.comment(a, b)
  local r = M.review()
  if not r then
    return
  end
  a = a or cursor_row()
  b = b or a
  local at = diff.anchor(V.map, a, b)
  local path = V.map[math.min(a, b)] and V.map[math.min(a, b)].path
  if not (at and path) then
    return notify("nothing to comment on here: move to a line of the diff", vim.log.levels.WARN)
  end
  ask("Comment: ", nil, function(body)
    act("comment", { rev = r.rev, path = path, side = at.side, line = at.line, ["end"] = at["end"], body = body },
      function(res)
        if res and res.comment then
          notify("comment waiting: s sends it")
        end
      end)
  end)
end

function M.reply()
  local c = thread_here()
  if not c then
    return notify("no conversation on this line", vim.log.levels.WARN)
  end
  V.open[c.id] = true
  ask("Reply: ", nil, function(body)
    act("reply", { comment = c.id, body = body })
  end)
end

function M.edit()
  local c = thread_here()
  local p = c and pending_in(c)
  if not p then
    return notify("nothing waiting to edit on this line", vim.log.levels.WARN)
  end
  ask("Edit: ", p.body, function(body)
    act("edit", { comment = p.id, body = body })
  end)
end

function M.discard(all)
  if all then
    local r = M.review()
    if not r or (r.waiting or 0) == 0 then
      return notify("nothing waiting")
    end
    if vim.fn.confirm("Discard all " .. r.waiting .. " waiting?", "&Discard\n&Keep", 2) == 1 then
      act("discard", {})
    end
    return
  end
  local c = thread_here()
  local p = c and pending_in(c)
  if not p then
    return notify("nothing waiting on this line", vim.log.levels.WARN)
  end
  act("discard", { comment = p.id })
end

function M.resolve()
  local c = thread_here()
  if not c then
    return notify("no conversation on this line", vim.log.levels.WARN)
  end
  act("resolve", { comment = c.id, resolved = c.state ~= "resolved" })
end

function M.send()
  local r = M.review()
  if not r then
    return
  end
  act("send", {}, function(res)
    if res and res.post then
      notify(string.format("sent to #%s (post %s)", tostring(r.channel), tostring(res.post)))
    end
  end)
end

local function the_round()
  local r = M.review()
  local rd = V.rounds_at and V.rounds_at[cursor_row()]
  if rd then
    return rd
  end
  if V.sel and V.sel.kind == "round" then
    for _, x in ipairs(r.rounds or {}) do
      if x.id == V.sel.id then
        return x
      end
    end
  end
  local proposed = vim.tbl_filter(function(x)
    return x.state == "proposed"
  end, r.rounds or {})
  if #proposed == 1 then
    return proposed[1]
  end
end

function M.accept()
  local rd = the_round()
  if not rd then
    return notify("which round? Move to its bar, or pick it on the left", vim.log.levels.WARN)
  end
  act("accept", { round = rd.id })
end

function M.reject()
  local rd = the_round()
  if not rd then
    return notify("which round? Move to its bar, or pick it on the left", vim.log.levels.WARN)
  end
  ask("Why reject round " .. (rd.n or "?") .. "? ", nil, function(reason)
    act("reject", { round = rd.id, reason = reason })
  end)
end

function M.toggle_uncommitted()
  local r = M.review()
  act("diff", { uncommitted = not (r.source and r.source.uncommitted) })
end

function M.fold()
  local c = thread_here()
  if c then
    V.open[c.id] = not V.open[c.id]
    return render()
  end
  local rd = V.rounds_at and V.rounds_at[cursor_row()]
  if rd then
    M.select({ kind = "round", id = rd.id })
  end
end

local function jump(rows, dir)
  local here = cursor_row()
  local pick
  for _, row in ipairs(rows) do
    if (dir > 0 and row > here and (not pick or row < pick)) or (dir < 0 and row < here and (not pick or row > pick)) then
      pick = row
    end
  end
  if pick then
    vim.api.nvim_win_set_cursor(V.diff_win, { pick, 0 })
  end
end

function M.next_change(dir)
  jump(diff.changes(V.map), dir)
end

function M.next_thread(dir)
  jump(V.thread_rows or {}, dir)
end

function M.select(sel)
  V.sel = sel
  render()
  if vim.api.nvim_win_is_valid(V.diff_win) then
    pcall(vim.api.nvim_win_set_cursor, V.diff_win, { 1, 0 })
  end
end

function M.help()
  local keys = {
    "j k        line",
    "]c [c      next, previous change",
    "]n [n      next, previous conversation",
    "h l        the files, then the diff",
    "V          select lines",
    "c          comment on the line or lines",
    "r          reply in the conversation",
    "↩          open or fold it (a round: its diff)",
    "i          edit what's waiting under the cursor",
    "d D        discard it; everything waiting",
    "R          resolve, or bring back",
    "s          send what's waiting, as one post",
    "a x        accept, reject the agent's round",
    "t          the branch alone, or uncommitted too",
    "q          close",
  }
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, keys)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = 50,
    height = #keys,
    row = 3,
    col = math.max(0, math.floor((vim.o.columns - 50) / 2)),
    border = "rounded",
    title = " review keys ",
    style = "minimal",
  })
  vim.keymap.set("n", "q", function()
    pcall(vim.api.nvim_win_close, win, true)
  end, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", function()
    pcall(vim.api.nvim_win_close, win, true)
  end, { buffer = buf, nowait = true })
end

-- ── windows and keys ────────────────────────────────────────────────────────

local function scratch(name)
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "wipe"
  vim.bo[b].swapfile = false
  vim.bo[b].modifiable = false
  pcall(vim.api.nvim_buf_set_name, b, name)
  return b
end

local function tree_pick()
  local what = V.rows and V.rows[vim.api.nvim_win_get_cursor(V.tree_win)[1]]
  if what then
    M.select(what)
    if vim.api.nvim_win_is_valid(V.diff_win) then
      vim.api.nvim_set_current_win(V.diff_win)
    end
  end
end

local function keys()
  local function map(buf, mode, lhs, fn, desc)
    vim.keymap.set(mode, lhs, fn, { buffer = buf, nowait = true, silent = true, desc = "pointman: " .. desc })
  end
  for _, buf in ipairs({ V.tree_buf, V.diff_buf }) do
    map(buf, "n", "q", M.close, "close the review")
    map(buf, "n", "g?", M.help, "the review's keys")
    map(buf, "n", "s", M.send, "send what's waiting")
    map(buf, "n", "t", M.toggle_uncommitted, "the branch alone, or uncommitted too")
    map(buf, "n", "D", function()
      M.discard(true)
    end, "discard everything waiting")
    map(buf, "n", "a", M.accept, "accept the round")
    map(buf, "n", "x", M.reject, "reject the round")
  end
  map(V.tree_buf, "n", "<CR>", tree_pick, "show it")
  map(V.tree_buf, "n", "l", tree_pick, "show it")
  map(V.diff_buf, "n", "h", function()
    vim.api.nvim_set_current_win(V.tree_win)
  end, "the files")
  map(V.diff_buf, "n", "c", function()
    M.comment()
  end, "comment on this line")
  map(V.diff_buf, "x", "c", function()
    local a, b = vim.fn.line("v"), vim.fn.line(".")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    M.comment(a, b)
  end, "comment on these lines")
  map(V.diff_buf, "n", "r", M.reply, "reply")
  map(V.diff_buf, "n", "i", M.edit, "edit what's waiting")
  map(V.diff_buf, "n", "d", function()
    M.discard(false)
  end, "discard what's waiting")
  map(V.diff_buf, "n", "R", M.resolve, "resolve, or bring back")
  map(V.diff_buf, "n", "<CR>", M.fold, "open or fold the conversation")
  map(V.diff_buf, "n", "]c", function()
    M.next_change(1)
  end, "next change")
  map(V.diff_buf, "n", "[c", function()
    M.next_change(-1)
  end, "previous change")
  map(V.diff_buf, "n", "]n", function()
    M.next_thread(1)
  end, "next conversation")
  map(V.diff_buf, "n", "[n", function()
    M.next_thread(-1)
  end, "previous conversation")
end

--- Opens `review` (a review as the extension gives it) in this Neovim, and follows it.
function M.open(review)
  M.hl()
  store.put(review)
  if M.is_open() then
    if V.id == review.id then
      if V.tab and vim.api.nvim_tabpage_is_valid(V.tab) then
        vim.api.nvim_set_current_tabpage(V.tab)
      end
      return render()
    end
    M.close()
  end
  V = { id = review.id, open = {}, sel = { kind = "file", index = 1 } }
  if cfg().open == "split" then
    vim.cmd("leftabove vsplit")
    V.diff_win = vim.api.nvim_get_current_win()
    vim.cmd("leftabove vsplit")
    V.tree_win = vim.api.nvim_get_current_win()
  else
    vim.cmd("tabnew")
    V.tab = vim.api.nvim_get_current_tabpage()
    V.tree_win = vim.api.nvim_get_current_win()
    vim.cmd("rightbelow vsplit")
    V.diff_win = vim.api.nvim_get_current_win()
  end
  V.tree_buf = scratch("pointman://review/" .. review.id .. "/files")
  V.diff_buf = scratch("pointman://review/" .. review.id .. "/diff")
  vim.api.nvim_win_set_buf(V.tree_win, V.tree_buf)
  vim.api.nvim_win_set_buf(V.diff_win, V.diff_buf)
  for _, w in ipairs({ V.tree_win, V.diff_win }) do
    vim.wo[w].number = false
    vim.wo[w].relativenumber = false
    vim.wo[w].wrap = false
    vim.wo[w].foldenable = false
  end
  vim.wo[V.tree_win].cursorline = true
  vim.wo[V.tree_win].winfixwidth = true
  vim.wo[V.tree_win].signcolumn = "no"
  vim.wo[V.diff_win].signcolumn = "no"
  vim.wo[V.diff_win].statuscolumn = "%#LineNr#%{v:lua.pointman_statuscol()} "
  pcall(vim.api.nvim_win_set_width, V.tree_win, cfg().tree_width)
  keys()
  store.on_change("view", function(r)
    if r.id == V.id then
      vim.schedule(render)
    end
  end)
  if cfg().follow then
    store.watch(review.id)
  end
  render()
  vim.api.nvim_set_current_win(V.diff_win)
end

function M.close()
  if V.id then
    store.unwatch(V.id)
  end
  store.off("view")
  if V.tab and vim.api.nvim_tabpage_is_valid(V.tab) and #vim.api.nvim_list_tabpages() > 1 then
    pcall(vim.cmd, vim.api.nvim_tabpage_get_number(V.tab) .. "tabclose")
  else
    for _, w in ipairs({ V.diff_win, V.tree_win }) do
      if w and vim.api.nvim_win_is_valid(w) and #vim.api.nvim_list_wins() > 1 then
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
  end
  V = {}
end

-- for the tests: what the view holds now
function M._state()
  return V
end

return M
