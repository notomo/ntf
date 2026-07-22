# ntf

Dependency-free neovim test CLI. Self-hosted: ntf runs its own specs.

## Gates (run before finishing any change)

- `make test` — specs pass (ntf runs itself)
- `make check` — lua-language-server reports no problems
  (set `CHECK_VIMRUNTIME` to your nvim runtime dir if it is not at the default)
- `stylua --config-path spec/.shared/stylua.toml lua spec/lua bin/ntf` — no diff
- `make require_lint` — enforces the require direction in `spec/require_lint.json`
  (the `ntf.core` engine layer stays self-contained; editor-facing layers depend
  on it, never the reverse)
- `make comment_lint` — enforces the comment form below over `lua/` (the doc
  sources listed in `spec/doc_config.json` are exempt for their `---` prose)
- `make mutation` — after changing `lua/`: must exit 0. It passes
  `--mutation-strict`, so any SURVIVED or NO COVERAGE mutant already fails the
  exit code — kill each survivor with a spec, and reach each no-coverage mutant
  with one (restructuring so the code is callable from a spec if need be, as
  `coverage/collector.lua`'s `line_hook` was split out); or — only when genuinely
  undetectable — add a `spec/mutation_baseline.json` entry with its rationale
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
- Express structure with LuaCATS (`@class/@field/@param/@return/@type`). Comments
  follow `spec/.shared/script/comment_lint.md`, which `make comment_lint`
  enforces — read it before writing one. Its `WHY:`/`NOT:` pair in practice: see
  `driver.lua` on SIGKILL vs `vim.system`'s SIGTERM, or `mutation/splice.lua` on
  its own module vs part of operators. Outside that rule's `lua/` scope, keep the
  comments genvdoc extracts (e.g. `coverage/highlight_group.lua`) and the ones in
  the snippets `spec/lua/ntf/doc.lua` renders.
- Every code/command element in the generated docs must be backed by something
  `spec/lua/ntf/doc.lua` executes during `make doc` (runnable snippet files in
  `spec/lua/ntf/doc/`, commands assembled from verified runs); no unverified
  snippets.
