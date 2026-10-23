-- pointman.socket: the node's local socket, one JSON line each way. Lines can be
-- in flight side by side, each answered by its `id`, so a long `ext.wait` never holds up a comment. One connection,
-- made when first needed and again after the node goes away (a restart): every request waiting then hears an error.

local M = {}

local uv = vim.uv or vim.loop

local C = { pipe = nil, connecting = false, queue = {}, pending = {}, next = 1, buf = "" }

--- Where the node listens: the setup's `socket`, else `$POINTMAN_SOCKET`, else the node's default.
function M.path()
  local cfg = require("pointman").config
  local p = cfg.socket or vim.env.POINTMAN_SOCKET or "~/.local/state/message-board/node.sock"
  return vim.fn.expand(p)
end

local function fail_all(err)
  local pending = C.pending
  C.pending = {}
  for _, cb in pairs(pending) do
    vim.schedule(function()
      cb(nil, err)
    end)
  end
end

local function drop(err)
  if C.pipe and not C.pipe:is_closing() then
    C.pipe:close()
  end
  C.pipe, C.connecting, C.buf = nil, false, ""
  fail_all(err)
  local queued = C.queue
  C.queue = {}
  for _, q in ipairs(queued) do
    vim.schedule(function()
      q.cb(nil, err)
    end)
  end
end

local function on_line(line)
  local ok, msg = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
  if not ok or type(msg) ~= "table" then
    return
  end
  local cb = C.pending[msg.id]
  if cb then
    C.pending[msg.id] = nil
    vim.schedule(function()
      cb(msg)
    end)
  end
end

local function send(req, cb)
  local id = C.next
  C.next = C.next + 1
  req.id = id
  C.pending[id] = cb
  C.pipe:write(vim.json.encode(req) .. "\n", function(err)
    if err then
      C.pending[id] = nil
      vim.schedule(function()
        cb(nil, "writing to the node: " .. err)
      end)
    end
  end)
end

local function connect()
  C.connecting = true
  local pipe = uv.new_pipe(false)
  local path = M.path()
  pipe:connect(path, function(err)
    if err then
      pipe:close()
      C.pipe = nil
      drop("no node at " .. path .. " (" .. err .. ")")
      return
    end
    C.pipe, C.connecting = pipe, false
    pipe:read_start(function(rerr, chunk)
      if rerr or not chunk then
        drop(rerr and ("the node: " .. rerr) or "the node went away")
        return
      end
      C.buf = C.buf .. chunk
      while true do
        local nl = C.buf:find("\n", 1, true)
        if not nl then
          break
        end
        local line = C.buf:sub(1, nl - 1)
        C.buf = C.buf:sub(nl + 1)
        on_line(line)
      end
    end)
    local queued = C.queue
    C.queue = {}
    for _, q in ipairs(queued) do
      send(q.req, q.cb)
    end
  end)
end

--- Sends `req` (a table; its `id` is set here) and calls `cb(answer)` with the node's line, or `cb(nil, err)` when
--- there's no node or it went away. Always on the main loop.
function M.request(req, cb)
  if C.pipe then
    send(req, cb)
    return
  end
  C.queue[#C.queue + 1] = { req = req, cb = cb }
  if not C.connecting then
    connect()
  end
end

--- Closes the connection; anything waiting hears that it was closed.
function M.close()
  drop("closed")
end

return M
