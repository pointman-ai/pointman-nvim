local T = require("tests.helpers")
local diff = require("pointman.diff")

local PATCH = table.concat({
  "@@ -10,4 +10,5 @@ fn f()",
  " a",
  "-b",
  "+B",
  "+C",
  " d",
  "@@ -40,2 +41,2 @@",
  "-x",
  "+y",
  " z",
  "\\ No newline at end of file",
  "",
}, "\n")

return {
  {
    "a patch's lines carry both sides' numbers",
    function()
      local lines, map = diff.parse(PATCH)
      T.eq(#lines, 10, "the trailing empty line and the no-newline note aren't lines")
      T.eq(map[1].kind, "hunk")
      T.eq({ map[2].old, map[2].new }, { 10, 10 }, "context")
      T.eq({ map[3].kind, map[3].old, map[3].new }, { "del", 11, nil })
      T.eq({ map[4].kind, map[4].new, map[5].new }, { "add", 11, 12 })
      T.eq({ map[6].old, map[6].new }, { 12, 13 })
      T.eq({ map[8].old, map[9].new, map[10].old, map[10].new }, { 40, 41, 41, 42 })
    end,
  },
  {
    "a line is found on its side",
    function()
      local _, map = diff.parse(PATCH)
      T.eq(diff.row_of(map, "new", 12), 5)
      T.eq(diff.row_of(map, "old", 11), 3, "a deleted line, by its old number")
      T.eq(diff.row_of(map, "new", 11), 4, "not the deleted line that had 11 on the old side")
      T.eq(diff.row_of(map, "new", 999), nil)
    end,
  },
  {
    "a selection anchors to the new file's lines, or the old's when it's all deleted",
    function()
      local _, map = diff.parse(PATCH)
      T.eq(diff.anchor(map, 2, 5), { side = "new", line = 10, ["end"] = 12 })
      T.eq(diff.anchor(map, 5, 2), { side = "new", line = 10, ["end"] = 12 }, "either way round")
      T.eq(diff.anchor(map, 3, 3), { side = "old", line = 11, ["end"] = 11 })
      T.eq(diff.anchor(map, 1, 1), nil, "a hunk's header")
    end,
  },
  {
    "each run of changes starts once",
    function()
      local _, map = diff.parse(PATCH)
      T.eq(diff.changes(map), { 3, 8 })
    end,
  },
  {
    "the fixture's gc patch maps line 503 and 1014–1016",
    function()
      local line = io.lines(T.root() .. "/tests/fixture/review-fixture.jsonl")()
      local review = vim.json.decode(line).res.result.review
      local _, map = diff.parse(review.files[1].patch)
      local r503 = diff.row_of(map, "new", 503)
      T.ok(r503 and map[r503].kind == "add", "503 is an added line")
      T.ok(diff.row_of(map, "new", 1014) and diff.row_of(map, "new", 1016), "1014–1016 are shown")
    end,
  },
}
