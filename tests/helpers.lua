-- What the tests share: asserts, waiting on the event loop, the stand-in node, and stubs for what a person types.

local M = {}

function M.eq(got, want, what)
  if not vim.deep_equal(got, want) then
    error(string.format("%s\n  got:  %s\n  want: %s", what or "not equal", vim.inspect(got), vim.inspect(want)), 2)
  end
end

function M.ok(cond, what)
  if not cond then
    error(what or "not true", 2)
  end
end

function M.has(text, part, what)
  if type(text) ~= "string" or not text:find(part, 1, true) then
    error(string.format("%s\n  %s\n  doesn't have: %s", what or "missing", vim.inspect(text), part), 2)
  end
end

--- Runs the event loop until `cond()` is true, or fails after `ms`.
function M.until_(cond, ms, what)
  if not vim.wait(ms or 3000, cond, 10) then
    error("waited in vain: " .. (what or "?"), 2)
  end
end

M.notes = {}
local real_notify, real_input = vim.notify, vim.ui.input
vim.notify = function(msg, level)
  M.notes[#M.notes + 1] = { msg = msg, level = level }
end

--- What vim.ui.input answers next, in order.
M.typed = {}
vim.ui.input = function(opts, cb)
  local text = table.remove(M.typed, 1)
  M.prompts = M.prompts or {}
  M.prompts[#M.prompts + 1] = opts and opts.prompt
  cb(text)
end

function M.last_note()
  return M.notes[#M.notes] and M.notes[#M.notes].msg or ""
end

function M.root()
  return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
end

--- A stand-in node on a socket of its own, and the plugin pointed at it.
function M.node(opts)
  -- a screen wide enough that a folded conversation's line isn't cut (headless is 80 by 24)
  vim.o.columns, vim.o.lines = 220, 60
  local sock = vim.fn.tempname() .. ".sock"
  local node = require("tests.fake_node").start(sock, M.root() .. "/tests/fixture/review-fixture.jsonl")
  require("pointman").setup(vim.tbl_extend("force", { socket = sock, follow = true, wait = 60 }, opts or {}))
  M.current = node
  return node
end

--- After each test: no view, no connection, no node, nothing kept.
function M.reset()
  pcall(function()
    require("pointman.view").close()
  end)
  require("pointman.socket").close()
  if M.current then
    M.current.stop()
    M.current = nil
  end
  local store = require("pointman.store")
  store.reviews, store.watching = {}, {}
  M.notes, M.typed, M.prompts = {}, {}, {}
  vim.cmd("silent! %bwipeout!")
end

M.real_notify, M.real_input = real_notify, real_input

return M
