-- pointman.nvim's commands, there before setup() (which they call with the defaults if it hasn't run).
if vim.g.loaded_pointman then
  return
end
vim.g.loaded_pointman = true

vim.api.nvim_create_user_command("PointmanReview", function(o)
  require("pointman").review(o.args)
end, { nargs = "?", desc = "Open a review: @agent, a folder, a PR link or a review id (none: this repo's)" })

vim.api.nvim_create_user_command("PointmanReviews", function()
  require("pointman").pick()
end, { desc = "Pick one of this machine's reviews" })

vim.api.nvim_create_user_command("PointmanSend", function()
  require("pointman.files").send()
end, { desc = "Send what's waiting in the review, as one post" })

vim.api.nvim_create_user_command("PointmanClose", function()
  require("pointman.view").close()
end, { desc = "Close the review" })
