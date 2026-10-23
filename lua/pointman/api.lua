-- pointman.api: the review extension's verbs through the node's `ext.call`, and its
-- `review.changed` through `ext.wait`. Each callback gets `(result, err)`: `err` is `{code, message}`, with `code`
-- one of the extension's (`not_found`, `stale`, `refused`, `invalid`, `timeout`) or nil for the node or socket's own.

local socket = require("pointman.socket")

local M = {}

local function cfg()
  return require("pointman").config
end

--- `review.<verb>` with `params`.
function M.call(verb, params, cb)
  local kind = verb:find("%.") and verb or ("review." .. verb)
  socket.request({ op = "ext.call", extension = cfg().extension, kind = kind, params = params or {} }, function(ans, err)
    if not ans then
      return cb(nil, { message = err })
    end
    if ans.ok then
      return cb(ans.result or {})
    end
    cb(nil, { code = ans.code, message = ans.error or "it failed" })
  end)
end

--- Waits for the review's next change past `since`: `cb({rev, timeout})`, `rev` nil when the node has none yet.
function M.wait(review, since, cb)
  local req = {
    op = "ext.wait",
    extension = cfg().extension,
    event = "review.changed",
    key = review,
    since = since,
    timeout = cfg().wait,
  }
  socket.request(req, function(ans, err)
    if not ans then
      return cb(nil, { message = err })
    end
    if ans.ok then
      return cb({ rev = ans.data and ans.data.rev, timeout = ans.timeout == true })
    end
    cb(nil, { code = ans.code, message = ans.error or "the wait failed" })
  end)
end

return M
