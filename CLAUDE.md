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
  `--strict`, so any SURVIVED or NO COVERAGE mutant already fails the
  exit code — kill each survivor with a spec, and reach each no-coverage mutant
  with one (restructuring so the code is callable from a spec if need be, as
  `coverage/collector.lua`'s `line_hook` was split out); or — only when genuinely
  undetectable — add a `baseline` entry with its rationale to `spec/mutation.json`,
  the one mutation policy file (`--config`).
  When that rationale rests on a fact from another module or from the runtime,
  add an `invariant_spec` naming the test that pins the fact — the run fails as
  UNPINNED BASELINE once no test of that name passes.
  A whole file stays out of the run only through that file's `exclude` section,
  which requires a rationale per path and fails as
  UNUSED EXCLUDE when an entry covers no measurable file. Measure before adding
  one — `$(NTF) mutation --target=PATH --config=spec/mutation.json spec`
  reports what that path's mutants actually do — and say in the rationale
  whether the exclusion is structural or debt.
  `init_spec.lua` is listed in `exclude_spec`, so it still runs — the mutation
  gate is a superset of `make test`, which is why CI runs a mutation target
  instead of both — but it is never picked as a mutant's trial, so a mutant only
  it reaches comes back NO COVERAGE and has to be reached by a unit spec
- `make mutation_verify_baseline` — after editing the `baseline` of `spec/mutation.json`:
  must exit 0. It re-runs the listed mutants and nothing else
  (`ntf mutation verify-baseline`) and fails any a test now kills (reported
  BASELINE KILLABLE) — kill it with a spec instead, or fix the entry. Kept out of
  `make mutation` so its hot path stays cheap
- `make mutation_ci` — what CI runs in place of the two above: one pass both
  scores the mutants and verifies the baseline entries
  (`ntf mutation --strict --verify-baseline`), so the suite is run once
  rather than once per target to map its coverage. Locally prefer the two
  narrower targets; run this only to reproduce a CI failure
- `make doc` — only after changing the CLI or the test API; regenerates
  `README.md` and `doc/ntf.txt`

## Conventions

- Test API is explicit, never global:
  `local describe, it = require("ntf").describe, require("ntf").it`. Do not inject globals.
- The CLI is a command tree defined once in `lua/ntf/core/controller/args.lua`
  (`M.root`): each command names the flags it accepts, so a flag that means
  nothing to a command is rejected there instead of being checked for after
  parsing. `usage()` and the docs derive from the tree — do not duplicate either
  list. Positional arguments are spec paths under every command; only leading
  tokens name a command.
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
