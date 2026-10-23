-- pointman.store: the reviews this Neovim has, as the extension last gave them, and the wait that keeps each current.
-- Every verb answers with the whole review, so a view never asks twice; a change made elsewhere (the pane, the agent)
-- comes as `review.changed` with a higher `rev`, and the review is got again. Views listen with `on_change`.

local api = require("pointman.api")

local M = { reviews = {}, listeners = {}, watching = {} }

--- Keeps `review` if it's newer than what's kept (or nothing is), and tells the listeners.
function M.put(review)
  if type(review) ~= "table" or not review.id then
    return
  end
  local had = M.reviews[review.id]
  if had and (had.rev or 0) > (review.rev or 0) then
    return
  end
  M.reviews[review.id] = review
  for _, fn in pairs(M.listeners) do
    pcall(fn, review)
  end
end

function M.on_change(name, fn)
  M.listeners[name] = fn
end

function M.off(name)
  M.listeners[name] = nil
end

--- Gets the review again and keeps it: `cb(review, err)`.
function M.refresh(id, cb)
  api.call("get", { review = id }, function(res, err)
    if res and res.review then
      M.put(res.review)
    end
    if cb then
      cb(res and res.review, err)
    end
  end)
end

--- Follows the review: waits on its `review.changed`, gets it again when its rev moves past ours, and waits again,
--- until `unwatch`. A wait with nothing kept (the node or extension restarted) gets it again too. With the node gone,
--- it tries again every few seconds.
function M.watch(id)
  if M.watching[id] then
    return
  end
  local gen = {}
  M.watching[id] = gen
  local function loop()
    if M.watching[id] ~= gen then
      return
    end
    local have = M.reviews[id]
    api.wait(id, have and have.rev or 0, function(res, err)
      if M.watching[id] ~= gen then
        return
      end
      if not res then
        local delay = err and err.code == "not_found" and 10000 or 3000
        vim.defer_fn(loop, delay)
        return
      end
      local now = M.reviews[id]
      if (res.rev and res.rev > (now and now.rev or 0)) or (res.rev == nil and res.timeout) then
        M.refresh(id, function()
          loop()
        end)
      else
        loop()
      end
    end)
  end
  loop()
end

function M.unwatch(id)
  M.watching[id] = nil
end

--- The open review whose folder holds `path` (an absolute file path), if this Neovim has one.
function M.for_path(path)
  local best
  for _, r in pairs(M.reviews) do
    local folder = r.folder and (r.folder:gsub("/$", "") .. "/")
    if r.state ~= "closed" and folder and path:sub(1, #folder) == folder then
      if not best or #r.folder > #best.folder then
        best = r
      end
    end
  end
  return best
end

return M
