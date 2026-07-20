# ntf

Dependency-free neovim test CLI. Self-hosted: ntf runs its own specs.

## Gates (run before finishing any change)

- `make test` — specs pass (ntf runs itself)
- `make check` — lua-language-server reports no problems
  (set `CHECK_VIMRUNTIME` to your nvim runtime dir if it is not at the default)
- `stylua --config-path spec/.shared/stylua.toml lua spec/lua bin/ntf` — no diff
- `make mutation` — after changing `lua/`: exits 0 and flags no SURVIVED and
  no NO COVERAGE mutant; kill each survivor with a spec, and reach each
  no-coverage mutant with one (restructuring so the code is callable from a
  spec if need be, as `coverage/collector.lua`'s `line_hook` was split out);
  or — only when genuinely undetectable — add a `spec/mutation_baseline.json`
  entry with its rationale
- `make doc` — only after changing CLI flags or the test API; regenerates
  `README.md` and `doc/ntf.txt`

## Conventions

- Test API is explicit, never global:
  `local describe, it = require("ntf").describe, require("ntf").it`. Do not inject globals.
- CLI flags are defined once in `lua/ntf/core/controller/args.lua` (`M.flags`); `usage()` and
  the docs derive from it — do not duplicate the list.
- `README.md` and `doc/ntf.txt` are generated from `spec/lua/ntf/doc.lua`. Edit
  that, then `make doc`; never hand-edit the outputs.
- `spec/.shared/` is cloned from notomo/workflow (gitignored); `make` clones it on
  first run.
- Express structure with LuaCATS (`@class/@field/@param/@return/@type`). Commit
  messages carry the "why"; a code comment exists only for the non-obvious "why
  not" (rejected alternatives, constraints), written carefully; never to restate
  what code does. A "why not" takes the shape **"X rather than Y, because Z"**: Y
  is the road not taken (one a reader would plausibly take), and Z the constraint
  that forecloses it, invisible in this file — see `driver.lua` on SIGKILL vs
  `vim.system`'s SIGTERM, or `mutation/splice.lua` on its own module vs part of
  operators. An outside fact on its own is still a "why" and belongs in the commit
  message; and if everything the comment names is right there in the code below
  it, delete the comment. Exception:
  doc-source comments — `---` descriptions on the public API, comments genvdoc
  extracts (e.g. `coverage/highlight_group.lua`), and comments in snippets
  `spec/lua/ntf/doc.lua` renders — keep them.
- Every code/command element in the generated docs must be backed by something
  `spec/lua/ntf/doc.lua` executes during `make doc` (runnable snippet files in
  `spec/lua/ntf/doc/`, commands assembled from verified runs); no unverified
  snippets.
