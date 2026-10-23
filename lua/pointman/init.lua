-- pointman.nvim: review code with an agent from Neovim, through your Pointman node. The review lives on the node, kept by the review extension; this plugin is one view of it and
-- the Pointman pane is the other, so a comment made in one shows in the other.
--
--   :PointmanReview [@agent | folder | PR link | rv_id]   open a review (no argument: this repo's)
--   <leader>hc   comment on the line or selection, in any file under review   (as neo-herdr's)
--   <leader>hs   send what's waiting, as one post that wakes the agent          (as neo-herdr's)
--   g?           in the review: its keys

local M = {}

M.config = {
  -- the node's socket: nil is $POINTMAN_SOCKET, else ~/.local/state/message-board/node.sock
  socket = nil,
  -- the extension that keeps reviews
  extension = "review",
  -- the review in a tab of its own ("tab"), or as splits beside the window you're in ("split")
  open = "tab",
  tree_width = 40,
  -- follow each open review: changes from the pane or the agent show as they come (ext.wait)
  follow = true,
  -- seconds each wait on the node lasts before it's asked again (1 to 60)
  wait = 60,
  -- show the conversations under their lines in your own files too, not only in the review
  in_files = true,
  keymaps = { prefix = "<leader>h", comment = "c", send = "s" },
}

local function notify(msg, level)
  vim.notify("[pointman] " .. msg, level or vim.log.levels.INFO)
end

local configured = false

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  configured = true
  require("pointman.view").hl()
  local km = M.config.keymaps
  if km and km.prefix then
    vim.keymap.set("n", km.prefix .. km.comment, function()
      require("pointman.files").comment()
    end, { desc = "pointman: comment on this line" })
    vim.keymap.set("x", km.prefix .. km.comment, function()
      local a, b = vim.fn.line("v"), vim.fn.line(".")
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
      require("pointman.files").comment(a, b)
    end, { desc = "pointman: comment on these lines" })
    vim.keymap.set("n", km.prefix .. km.send, function()
      require("pointman.files").send()
    end, { desc = "pointman: send what's waiting" })
  end
  if M.config.in_files then
    require("pointman.files").attach()
  end
end

local function ensure()
  if not configured then
    M.setup({})
  end
end

local function git_top(dir)
  local out = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  if vim.v.shell_error == 0 and out[1] then
    return out[1]
  end
end

--- Opens a review: `arg` is `@agent`, a folder, a PR link or a review's id; with none, the open review of this repo,
--- else a new one of it.
function M.review(arg)
  ensure()
  local api = require("pointman.api")
  local view = require("pointman.view")
  local function show(res, err)
    if err then
      return notify(err.message or "no review", vim.log.levels.ERROR)
    end
    if res and res.review then
      view.open(res.review)
    end
  end
  arg = arg and vim.trim(arg) or ""
  if arg:match("^rv_") then
    return api.call("get", { review = arg }, show)
  elseif arg:match("^@") then
    return api.call("open", { agent = arg:sub(2) }, show)
  elseif arg:match("^https?://") then
    return api.call("open", { pr = arg }, show)
  elseif arg ~= "" then
    return api.call("open", { folder = vim.fn.fnamemodify(vim.fn.expand(arg), ":p"):gsub("/$", "") }, show)
  end
  local top = git_top(vim.fn.getcwd()) or vim.fn.getcwd()
  api.call("list", { folder = top }, function(res, err)
    if err then
      return notify(err.message or "no reviews", vim.log.levels.ERROR)
    end
    local open = vim.tbl_filter(function(r)
      return r.state ~= "closed"
    end, res.reviews or {})
    if open[1] then
      return api.call("get", { review = open[1].id }, show)
    end
    api.call("open", { folder = top }, show)
  end)
end

--- Picks one of the node's reviews and opens it.
function M.pick()
  ensure()
  require("pointman.api").call("list", {}, function(res, err)
    if err then
      return notify(err.message or "no reviews", vim.log.levels.ERROR)
    end
    local reviews = res.reviews or {}
    if #reviews == 0 then
      return notify("no reviews open on this machine")
    end
    vim.ui.select(reviews, {
      prompt = "Review:",
      format_item = function(r)
        local waiting = (r.waiting or 0) > 0 and (" · " .. r.waiting .. " to send") or ""
        local proposed = (r.proposed or 0) > 0 and (" · " .. r.proposed .. " round waiting") or ""
        return (r.title or r.id) .. (r.agent and (" · @" .. r.agent) or "") .. waiting .. proposed
      end,
    }, function(r)
      if r then
        M.review(r.id)
      end
    end)
  end)
end

return M
