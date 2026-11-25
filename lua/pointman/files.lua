-- pointman.files: the review from your own files, as neo-herdr did it. `<leader>hc` comments on the line (or
-- selection) of the file you're in, in the open review of its repo, and `<leader>hs` sends; each conversation shows
-- under its line of the file, as in the review. A file's lines are the head's (with what isn't committed when the
-- review includes it), so its comments are on the new side.

local api = require("pointman.api")
local store = require("pointman.store")

local M = {}

local NS = vim.api.nvim_create_namespace("pointman_files")

local function notify(msg, level)
  vim.notify("[pointman] " .. msg, level or vim.log.levels.INFO)
end

--- The review for the file in `buf`: one this Neovim has, else the newest open one the node has for its folder.
local function review_for(buf, cb)
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or path:match("^%w+://") then
    return cb(nil, "this isn't a file")
  end
  local have = store.for_path(path)
  if have then
    return cb(have, nil, path)
  end
  api.call("list", { folder = vim.fn.fnamemodify(path, ":h") }, function(res, err)
    local open = vim.tbl_filter(function(r)
      return r.state ~= "closed"
    end, (res and res.reviews) or {})
    if not open[1] then
      return cb(nil, err and err.message or "no open review for this file: :PointmanReview opens one")
    end
    store.refresh(open[1].id, function(r, gerr)
      cb(r, gerr and gerr.message, path)
    end)
  end)
end

local function relative(r, path)
  local folder = r.folder:gsub("/$", "") .. "/"
  return path:sub(1, #folder) == folder and path:sub(#folder + 1) or nil
end

function M.comment(a, b)
  local buf = vim.api.nvim_get_current_buf()
  a = a or vim.fn.line(".")
  b = b or a
  if a > b then
    a, b = b, a
  end
  review_for(buf, function(r, err, path)
    if not r then
      return notify(err, vim.log.levels.WARN)
    end
    local rel = relative(r, path)
    if not rel then
      return notify("this file isn't in " .. r.folder, vim.log.levels.WARN)
    end
    vim.ui.input({ prompt = string.format("Comment on %s:%d: ", rel, a) }, function(body)
      if not body or vim.trim(body) == "" then
        return
      end
      api.call("comment", { review = r.id, rev = r.rev, path = rel, side = "new", line = a, ["end"] = b, body = body },
        function(res, cerr)
          if res and res.review then
            store.put(res.review)
            notify("comment waiting: " .. require("pointman").config.keymaps.prefix .. "s sends it")
          elseif cerr then
            notify(cerr.message or "it failed", vim.log.levels.WARN)
          end
        end)
    end)
  end)
end

function M.send()
  local view = require("pointman.view")
  local function send(r)
    api.call("send", { review = r.id }, function(res, err)
      if res and res.review then
        store.put(res.review)
        notify(string.format("sent to #%s (post %s)", tostring(r.channel), tostring(res.post)))
      elseif err then
        notify(err.message or "it failed", vim.log.levels.WARN)
      end
    end)
  end
  if view.is_open() and view.review() then
    return send(view.review())
  end
  review_for(vim.api.nvim_get_current_buf(), function(r, err)
    if not r then
      return notify(err, vim.log.levels.WARN)
    end
    send(r)
  end)
end

--- Draws the review's conversations under their lines in `buf`, when it's a file of an open review.
function M.draw(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  local path = vim.api.nvim_buf_get_name(buf)
  local r = path ~= "" and store.for_path(path)
  local rel = r and relative(r, path)
  if not rel then
    return
  end
  local count = vim.api.nvim_buf_line_count(buf)
  for _, c in ipairs(r.comments or {}) do
    if c.path == rel and c.side == "new" and not c.outdated and c.state ~= "resolved" then
      local last = (c.replies and c.replies[#c.replies]) or c
      local line = math.min(c["end"] or c.line, count)
      local who = last.by or c.by or "?"
      local waiting = (c.state == "pending" or last.state == "pending") and " · waiting" or ""
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, line - 1, 0, {
        virt_lines = { {
          { "  ▸ ", "PointmanRound" },
          { who .. ": ", who == r.by and "PointmanYou" or "PointmanAgent" },
          { (vim.split(last.body or "", "\n")[1]), "PointmanDim" },
          { waiting, "PointmanWaiting" },
        } },
      })
    end
  end
end

function M.attach()
  local grp = vim.api.nvim_create_augroup("PointmanFiles", { clear = true })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWritePost" }, {
    group = grp,
    callback = function(ev)
      M.draw(ev.buf)
    end,
  })
  store.on_change("files", function()
    vim.schedule(function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        M.draw(vim.api.nvim_win_get_buf(w))
      end
    end)
  end)
end

return M
