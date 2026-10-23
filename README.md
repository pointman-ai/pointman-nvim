# pointman.nvim

Review code with an agent from Neovim. You comment on lines of a diff, send them as one post that wakes the agent,
and its answer shows under the line. Its fix comes as a round you accept or reject. The same review shows in
Pointman's review pane, so a comment made in one shows in the other.

```
 shipwright's gc fix          │ node/src/gc.rs
  agent's copy · origin/main…H│500  +    drop_index(&entry, 146);
  #15864 · @shipwright        │501  +        read_batch(&set, 62);
                              │502  +            close_state(&queue, 192);
  FILES                       │503  +            // read the queue, then the lis
 ▸~ node/src/gc.rs  +20 −1    │       ━━ Round 2 · @shipwright · +2 −1 · propose
                              │       ▸ shipwright: No: git ren… (2) · outdated
  ROUNDS                      │504  +            merge_state(&items, 132);
   Round 2 · @shipwright · +2 │505  +        load_cache(&items, 249);
                              │506  +    keep_items(&list, 87);
  1 outdated conversation     │507  +    wait_files(&batch, 60);
                              │508           count_cache(&rows, 62);
```

Neovim at 80×24 with round 2 proposed: the files and rounds on the left, the diff on the right, the round's bar and
the (now outdated) conversation under line 503.

It's built on [neo-herdr.nvim](https://github.com/jamescalam/neo-herdr.nvim) (comments sent as a batch) and
[neo-reviewr.nvim](https://github.com/jamescalam/neo-reviewr.nvim) (the files and the diff), talking to your Pointman
node instead of herdr. The review itself lives on the node, kept by Pointman's `review` extension.

## Requirements

- Neovim 0.10 or newer.
- A Pointman node on this machine, with the `review` extension (`pointman add review`). The plugin reaches it on the
  node's socket, `~/.local/state/message-board/node.sock`, through `ext.call` and `ext.wait`.

## Install

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "pointman-ai/pointman-nvim",
  config = function()
    require("pointman").setup()
  end,
}
```

`:checkhealth pointman` says whether the node and its review extension answer.

## Use

| Command | Does |
|---|---|
| `:PointmanReview` | This repo's open review, or a new one of it |
| `:PointmanReview @shipwright` | The review of an agent's copy |
| `:PointmanReview ~/code/app` | The review of a folder |
| `:PointmanReview https://github.com/…/pull/42` | A PR, checked out into a review copy |
| `:PointmanReviews` | Pick one of this machine's reviews |
| `:PointmanSend` | Send what's waiting, as one post |

**In the review**, the same letters as the Pointman pane:

| Key | Does |
|---|---|
| `j` `k` | Next, previous line |
| `]c` `[c` | Next, previous change |
| `]n` `[n` | Next, previous conversation |
| `h` `l` | The files, then the diff |
| `V` then `c` | Comment on the lines; `c` alone, on the line |
| `r` | Reply in the conversation |
| `↩` | Open or fold the conversation; on the left, show a file or a round's own diff |
| `i` | Edit what's waiting under the cursor |
| `d` `D` | Discard it; discard everything waiting (asks first) |
| `R` | Resolve the conversation, or bring it back |
| `s` | Send what's waiting, as one post that wakes the agent |
| `a` `x` | Accept, reject the agent's round (rejecting asks why) |
| `t` | The branch alone, or with what isn't committed |
| `g?` `q` | The keys; close |

**In any file under review**, as neo-herdr's: `<leader>hc` comments on the line or selection, `<leader>hs` sends.
Each conversation also shows under its line of the file.

Nothing reaches the agent until you send. A send from Neovim posts in the review's thread as your machine, naming you.
Agents never type in Neovim or touch its buffers: they change code in their own copy, and each change comes as a round.

## Setup (defaults)

```lua
require("pointman").setup({
  socket = nil,        -- the node's socket: nil is $POINTMAN_SOCKET, else ~/.local/state/message-board/node.sock
  extension = "review",
  open = "tab",        -- "tab", or "split" beside the window you're in
  tree_width = 40,
  follow = true,       -- show changes from the pane and the agent as they come
  wait = 60,           -- seconds each wait on the node lasts (1 to 60)
  in_files = true,     -- conversations under their lines in your own files too
  keymaps = { prefix = "<leader>h", comment = "c", send = "s" },
})
```

## How it works

- **One connection to the node's socket,** one JSON line each way, many in flight. A verb is
  `{"op": "ext.call", "extension": "review", "kind": "review.comment", "params": {…}}`, and every verb answers with
  the whole review, which the view draws.
- **Following a review** is `ext.wait` on its `review.changed`: the node answers once the review's `rev` passes the
  one Neovim has, and the plugin gets the review again. A wait that times out is asked again, so a restart of the node
  costs nothing.
- **A comment** carries the review's `rev`. If the diff has moved since, the extension says `stale`, and the plugin gets
  the review again for you to comment on the new lines.

## Tests

```
make test        # nvim --headless -u NONE -l tests/run.lua
```

They run against a stand-in node (`tests/fake_node.lua`) that answers from a recorded review
(`tests/fixture/review-fixture.jsonl`, its code made up): open, two comments, a send, the agent's answer, round 2
accepted and round 3 rejected.
