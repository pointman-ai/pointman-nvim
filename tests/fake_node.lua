-- A stand-in for the Pointman node: a Unix socket that answers `ext.call` and `ext.wait` lines from the review
-- fixture (a review from open to a rejected third round, its code made up), so the plugin's tests run with no node.
--
-- - Calls are answered in the fixture's order, per kind: the first `review.comment` gets exchange 4's answer, and so
--   on. `review.get` answers with the review as it stands now (the newest any answer gave), since a client gets it
--   whenever it likes.
-- - Waits are held until the test lets one go (`release`): then the next wait's answer, and the review moves on to
--   what the agent did meanwhile (the review the fixture gets next).

local uv = vim.uv or vim.loop

local M = {}

local function read_fixture(path)
  local out = {}
  for line in io.lines(path) do
    if line ~= "" then
      out[#out + 1] = vim.json.decode(line, { luanil = { object = true, array = true } })
    end
  end
  return out
end

function M.start(socket_path, fixture_path)
  local F = read_fixture(fixture_path)
  local node = { seen = {}, held = {}, calls = {}, waits = {}, after = {}, current = nil, missing = nil }
  for i, ex in ipairs(F) do
    local req = ex.req
    if req.op == "ext.call" and req.kind == "review.get" then
      if req.params.review ~= "rv_7" then
        node.missing = ex
      end
    elseif req.op == "ext.call" then
      node.calls[req.kind] = node.calls[req.kind] or {}
      table.insert(node.calls[req.kind], ex)
    elseif req.op == "ext.wait" then
      table.insert(node.waits, ex)
      -- what the review is once this wait has answered: the next get's review, if one comes before the next wait
      for j = i + 1, #F do
        local nx = F[j]
        if nx.req.op == "ext.wait" then
          break
        end
        if nx.req.kind == "review.get" and nx.res.result then
          node.after[#node.waits] = nx.res.result.review
          break
        end
      end
    end
  end
  local first_open = (node.calls["review.open"] or {})[1]
  node.current = first_open and first_open.res.result.review

  local function answer(client, id, res)
    local out = vim.deepcopy(res)
    out.id = id
    client:write(vim.json.encode(out) .. "\n")
  end

  local function handle(client, req)
    node.seen[#node.seen + 1] = req
    if req.op == "ext.wait" then
      node.held[#node.held + 1] = { client = client, req = req }
      return
    end
    if req.kind == "review.get" then
      if req.params.review ~= "rv_7" and node.missing then
        return answer(client, req.id, node.missing.res)
      end
      return answer(client, req.id, { ok = true, result = { review = node.current } })
    end
    local queue = node.calls[req.kind] or {}
    local ex = table.remove(queue, 1)
    if not ex then
      return answer(client, req.id, { error = "the stand-in has no more " .. tostring(req.kind), code = "not_found" })
    end
    if ex.res.result and ex.res.result.review then
      node.current = ex.res.result.review
    end
    answer(client, req.id, ex.res)
  end

  local server = uv.new_pipe(false)
  os.remove(socket_path)
  assert(server:bind(socket_path))
  server:listen(16, function(err)
    assert(not err, err)
    local client = uv.new_pipe(false)
    server:accept(client)
    local buf = ""
    client:read_start(function(rerr, chunk)
      if rerr or not chunk then
        client:close()
        return
      end
      buf = buf .. chunk
      while true do
        local nl = buf:find("\n", 1, true)
        if not nl then
          break
        end
        local line = buf:sub(1, nl - 1)
        buf = buf:sub(nl + 1)
        handle(client, vim.json.decode(line, { luanil = { object = true, array = true } }))
      end
    end)
  end)

  --- Lets the oldest held wait go with the next wait's answer; the review moves on as the fixture says.
  function node.release()
    local h = table.remove(node.held, 1)
    local n = #node.waits > 0 and (node.used or 0) + 1
    if not h or not node.waits[n] then
      return false
    end
    node.used = n
    if node.after[n] then
      node.current = node.after[n]
    end
    answer(h.client, h.req.id, node.waits[n].res)
    return true
  end

  --- The requests of one kind it has seen, oldest first.
  function node.requests(kind)
    return vim.tbl_filter(function(r)
      return r.kind == kind or r.event == kind
    end, node.seen)
  end

  function node.fixture(n)
    return F[n]
  end

  function node.stop()
    server:close()
    os.remove(socket_path)
  end

  return node
end

return M
