-- pointman.diff: a file's patch (GitHub's `patch` text, as a review's `files` carry it) as buffer lines, each mapped to
-- the old and new file's line numbers, and the places review comments anchor to: a side, and a first and last line.
-- Pure functions, so the headless tests check them without a node.

local M = {}

--- The patch's lines and, for each, `{kind, old, new}`: kind `hunk`, `ctx`, `add`, `del` or `meta`; `old` and `new`
--- the 1-based line numbers on each side (nil where a side has none).
function M.parse(patch)
  local lines, map = {}, {}
  local old, new
  for _, l in ipairs(vim.split(patch or "", "\n", { plain = true })) do
    local o, n = l:match("^@@ %-(%d+),?%d* %+(%d+)")
    local m
    if o then
      old, new = tonumber(o), tonumber(n)
      m = { kind = "hunk" }
    elseif l:sub(1, 1) == "\\" then
      m = nil -- "\ No newline at end of file": not a line of either file
    elseif not old then
      m = { kind = "meta" } -- before the first hunk: diff --git, index, ---, +++
    elseif l:sub(1, 1) == "+" then
      m = { kind = "add", new = new }
      new = new + 1
    elseif l:sub(1, 1) == "-" then
      m = { kind = "del", old = old }
      old = old + 1
    else
      m = { kind = "ctx", old = old, new = new }
      old, new = old + 1, new + 1
    end
    if m then
      lines[#lines + 1] = l
      map[#map + 1] = m
    end
  end
  -- a patch that ends in a newline leaves an empty last line that's no line of the file
  if lines[#lines] == "" and map[#map].kind == "ctx" then
    lines[#lines], map[#map] = nil, nil
  end
  return lines, map
end

--- The buffer line (1-based) showing `line` of `side` ("new" or "old"), or nil when the patch doesn't show it.
function M.row_of(map, side, line)
  for i, m in ipairs(map) do
    if (side == "old" and m.old == line and m.kind ~= "add") or (side ~= "old" and m.new == line and m.kind ~= "del") then
      return i
    end
  end
end

--- What a comment on buffer lines `a`..`b` anchors to: `{side, line, end}`. Lines of the new file where there are
--- any (context and added), else the old file's (a selection of only deleted lines). Nil on a hunk or meta line.
function M.anchor(map, a, b)
  if a > b then
    a, b = b, a
  end
  local new, old = {}, {}
  for i = a, b do
    local m = map[i]
    if m and m.new then
      new[#new + 1] = m.new
    end
    if m and m.kind == "del" then
      old[#old + 1] = m.old
    end
  end
  if #new > 0 then
    return { side = "new", line = new[1], ["end"] = new[#new] }
  end
  if #old > 0 then
    return { side = "old", line = old[1], ["end"] = old[#old] }
  end
end

--- The first line of each run of changes (added or deleted lines together), for ]c and [c.
function M.changes(map)
  local out, prev = {}, false
  for i, m in ipairs(map) do
    local changed = m.kind == "add" or m.kind == "del"
    if changed and not prev then
      out[#out + 1] = i
    end
    prev = changed
  end
  return out
end

return M
