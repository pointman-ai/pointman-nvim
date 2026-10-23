-- The review loop in Neovim against the stand-in node, step by step as the fixture goes: open shipwright's copy,
-- comment twice (in the review, then from the file), send, see the answer under the line, accept round 2, reject round
-- 3, and what's refused or isn't there.

local T = require("tests.helpers")
local diff = require("pointman.diff")

local function V()
  return require("pointman.view")._state()
end

local function tree()
  return table.concat(vim.api.nvim_buf_get_lines(V().tree_buf, 0, -1, false), "\n")
end

--- The virtual lines drawn under a row of the diff (or above row 1), as text.
local function under(row)
  local ns = vim.api.nvim_get_namespaces()["pointman_view"]
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(V().diff_buf, ns, { row - 1, 0 }, { row - 1, -1 }, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      local s = {}
      for _, chunk in ipairs(vl) do
        s[#s + 1] = chunk[1]
      end
      out[#out + 1] = table.concat(s)
    end
  end
  return table.concat(out, "\n")
end

local function row(line)
  return diff.row_of(V().map, "new", line)
end

local function review()
  return require("pointman.view").review()
end

local function opened(node)
  require("pointman").review("@shipwright")
  T.until_(function()
    return require("pointman.view").is_open() and review() ~= nil
  end, 3000, "the review to open")
  -- the follow's first wait reaches the node
  T.until_(function()
    return #node.held == 1
  end, 3000, "the first wait")
end

local function rev_is(n)
  T.until_(function()
    return review() and review().rev == n
  end, 3000, "rev " .. n)
end

return {
  {
    "the whole loop, as the fixture goes",
    function()
      local node = T.node()
      local view = require("pointman.view")

      -- 1–2: open shipwright's copy, and get it again: nothing changed
      opened(node)
      T.eq(node.requests("review.open")[1].params, node.fixture(1).req.params, "review.open's params")
      T.has(tree(), "shipwright's gc fix")
      T.has(tree(), "agent's copy · origin/main…HEAD · uncommitted too")
      T.has(tree(), "~ node/src/gc.rs  +19 −1")
      T.ok(row(503) and row(1014), "the diff shows 503 and 1014")
      local done
      require("pointman.store").refresh("rv_7", function()
        done = true
      end)
      T.until_(function()
        return done
      end)
      T.eq(review().rev, 1)

      -- 3: the follow's wait times out with the same rev, and waits again
      T.ok(node.release(), "the first wait goes")
      T.until_(function()
        return #node.held == 1
      end, 3000, "a second wait")
      T.eq(#node.requests("review.get"), 1, "no get for a rev it has")

      -- 4: comment on line 503 in the review
      vim.api.nvim_set_current_win(V().diff_win)
      vim.api.nvim_win_set_cursor(V().diff_win, { row(503), 0 })
      T.typed = { node.fixture(4).req.params.body }
      view.comment()
      rev_is(2)
      T.eq(node.requests("review.comment")[1].params, node.fixture(4).req.params, "the comment's params")
      T.has(under(row(503)), "james: A missing HEAD or index counts as quiet")
      T.has(under(row(503)), "1 waiting")
      T.has(tree(), "1 to send (s)")

      -- 5: comment on 1014–1016 from the file itself, as <leader>hc does
      local file = review().folder .. "/node/src/gc.rs"
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, file)
      local lines = {}
      for i = 1, 1100 do
        lines[i] = "line " .. i
      end
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.cmd("tabnew")
      vim.api.nvim_set_current_buf(buf)
      T.typed = { node.fixture(5).req.params.body }
      require("pointman.files").comment(1014, 1016)
      rev_is(3)
      T.eq(node.requests("review.comment")[2].params, node.fixture(5).req.params, "the file comment's params")
      T.has(T.prompts[#T.prompts], "node/src/gc.rs:1014")
      -- drawn under its line in the file too
      local fns = vim.api.nvim_get_namespaces()["pointman_files"]
      local marks = vim.api.nvim_buf_get_extmarks(buf, fns, 0, -1, { details = true })
      T.eq(#marks, 2, "both conversations show in the file")
      vim.cmd("tabprevious")

      -- 6: send both as one post
      view.send()
      rev_is(4)
      T.has(T.last_note(), "sent to #15864 (post 16901)")
      T.ok(not tree():find("to send", 1, true), "nothing waiting")

      -- 7–8: shipwright answers under c1: the follow gets it
      T.ok(node.release(), "the wait for the answer goes")
      rev_is(5)
      T.has(under(row(503)), "shipwright: No: git renames a lock file onto them")

      -- 9, 11: round 2 comes (a commit in shipwright's copy): c1's line was replaced, c2's moved down one
      T.until_(function()
        return #node.held == 1
      end)
      T.ok(node.release(), "the wait for round 2 goes")
      rev_is(6)
      T.has(tree(), "Round 2 · @shipwright")
      T.has(tree(), "proposed")
      T.has(tree(), "1 outdated conversation")
      T.ok(under(row(1017)):find("Name the lock file", 1, true), "c2 under its new last line, 1017")

      -- 10: a comment the diff moved under: refused as stale, and the review got again
      vim.api.nvim_win_set_cursor(V().diff_win, { row(1014), 0 })
      T.typed = { node.fixture(10).req.params.body }
      local gets = #node.requests("review.get")
      view.comment()
      T.until_(function()
        return T.last_note():find("the diff changed at rev 6", 1, true) ~= nil
      end, 3000, "the stale note")
      T.until_(function()
        return #node.requests("review.get") > gets
      end, 3000, "a get after stale")

      -- 12–13: accept round 2 (the only one proposed), then send the verdict
      view.accept()
      rev_is(7)
      T.eq(node.requests("review.accept")[1].params, node.fixture(12).req.params, "accept's params")
      T.has(tree(), "Round 2 · @shipwright · +")
      T.has(tree(), "✓ accepted")
      view.send()
      rev_is(8)
      local function shown()
        return table.concat(vim.api.nvim_buf_get_lines(V().diff_buf, 0, -1, false), "\n")
      end
      local before = shown()

      -- 14–17: round 3 comes (a commit in shipwright's copy, so in the files); reject it, saying why, then send
      T.until_(function()
        return #node.held == 1
      end)
      T.ok(node.release(), "the wait for round 3 goes")
      rev_is(9)
      T.has(tree(), "Round 3")
      T.ok(shown() ~= before, "round 3's line is in the diff")
      T.typed = { node.fixture(16).req.params.reason }
      view.reject()
      rev_is(10)
      T.eq(node.requests("review.reject")[1].params, node.fixture(16).req.params, "reject's params")
      T.has(tree(), "✗ rejected")
      T.eq(shown(), before, "the reject took round 3's line out again")
      view.send()
      rev_is(11)

      -- 18: nothing waiting: refused, in the extension's words
      view.send()
      T.until_(function()
        return T.last_note():find("nothing to send", 1, true) ~= nil
      end, 3000, "the refusal")
      T.eq(review().rev, 11, "nothing changed")
    end,
  },
  {
    "a review that isn't there says so",
    function()
      T.node()
      require("pointman").review("rv_99")
      T.until_(function()
        return T.last_note():find("no review rv_99 on mac-m4", 1, true) ~= nil
      end, 3000, "the not-found note")
      T.ok(not require("pointman.view").is_open())
    end,
  },
  {
    "with no node, it says where it looked",
    function()
      require("pointman").setup({ socket = vim.fn.tempname() .. ".sock" })
      require("pointman").review("@shipwright")
      T.until_(function()
        return T.last_note():find("no node at", 1, true) ~= nil
      end, 3000, "the no-node note")
    end,
  },
  {
    "the review's keys are the pane's letters",
    function()
      local node = T.node({ follow = false })
      require("pointman").review("@shipwright")
      T.until_(function()
        return require("pointman.view").is_open()
      end)
      local function keys(buf, mode)
        local out = {}
        for _, k in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
          out[k.lhs] = true
        end
        return out
      end
      local d, t = keys(V().diff_buf, "n"), keys(V().tree_buf, "n")
      for _, k in ipairs({ "c", "s", "r", "i", "d", "D", "R", "a", "x", "t", "q", "g?", "<CR>", "h", "]c", "[c", "]n", "[n" }) do
        T.ok(d[k], "the diff has " .. k)
      end
      for _, k in ipairs({ "<CR>", "l", "s", "a", "x", "q" }) do
        T.ok(t[k], "the files have " .. k)
      end
      T.ok(keys(V().diff_buf, "x")["c"], "c on a selection")
      T.eq(#node.held, 0, "no follow when it's off")
    end,
  },
}
