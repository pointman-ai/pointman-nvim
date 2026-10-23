-- The tests, headless: `nvim --headless -u NONE -l tests/run.lua` (or `make test`). Each tests/test_*.lua returns a
-- list of {name, fn}; a test fails when it errors. Exits 1 when any failed.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
package.path = root .. "/?.lua;" .. package.path
vim.cmd("runtime plugin/pointman.lua")

local T = require("tests.helpers")
local passed, failed = 0, {}
local only = vim.env.TEST
for _, file in ipairs(vim.fn.glob(root .. "/tests/test_*.lua", false, true)) do
  local mod = "tests." .. vim.fn.fnamemodify(file, ":t:r")
  for _, t in ipairs(require(mod)) do
    if not only or t[1]:find(only, 1, true) then
      local ok, err = xpcall(t[2], debug.traceback)
      T.reset()
      if ok then
        passed = passed + 1
        io.write("ok    " .. t[1] .. "\n")
      else
        failed[#failed + 1] = t[1]
        io.write("FAIL  " .. t[1] .. "\n" .. tostring(err) .. "\n")
      end
    end
  end
end
io.write(string.format("\n%d passed, %d failed\n", passed, #failed))
os.exit(#failed == 0 and 0 or 1)
