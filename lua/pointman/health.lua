-- :checkhealth pointman: the node's socket, and the review extension behind it.
local M = {}

function M.check()
  local h = vim.health
  h.start("pointman.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim 0.10 or newer is needed")
  end
  local path = require("pointman.socket").path()
  if vim.uv.fs_stat(path) then
    h.ok("the node's socket: " .. path)
  else
    return h.error("no node's socket at " .. path, { "Is the Pointman node running on this machine?",
      "Set `socket` in setup() if it listens elsewhere (`pointman-node run --socket`)." })
  end
  local done, got, err = false, nil, nil
  require("pointman.api").call("list", {}, function(res, e)
    done, got, err = true, res, e
  end)
  vim.wait(5000, function()
    return done
  end, 20)
  if not done then
    h.error("the node didn't answer in 5 s")
  elseif err and err.code == "not_found" then
    h.error("the node answers, but the review extension isn't running: " .. (err.message or ""),
      { "`pointman add review` installs it on this machine." })
  elseif err then
    h.error("review.list failed: " .. (err.message or "?"))
  else
    h.ok(string.format("the review extension answers: %d review(s) on this machine", #(got.reviews or {})))
  end
end

return M
