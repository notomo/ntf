# ntf

Dependency-free neovim test CLI. Self-hosted: ntf runs its own specs.

## Gates (run before finishing any change)

- `make test` — specs pass (ntf runs itself)
- `make check` — lua-language-server reports no problems
  (set `CHECK_VIMRUNTIME` to your nvim runtime dir if it is not at the default)
- `stylua --config-path "$WORKFLOW_DIR/stylua.toml" lua spec/lua bin/ntf` — no diff
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
  the one mutation policy file (`--config`), with
  `$(NTF) mutation baseline add --config=spec/mutation.json --mutant=PATH:ROW:COL:OPERATOR --rationale=...`,
  which writes the entry from the mutant the report names and runs no test
  (add `--replacement` only when that position holds more than one of the
  operator's mutants, as a forced branch does).
  When that rationale rests on a fact from another module or from the runtime,
  pass `--invariant-spec` naming the test that pins the fact — the run fails as
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
  (`ntf mutation baseline verify`) and fails any a test now kills (reported
  BASELINE KILLABLE) — kill it with a spec instead, or fix the entry. Kept out of
  `make mutation` so its hot path stays cheap
- `make mutation_ci` — what CI runs in place of the two above: one pass both
  scores the mutants and verifies the baseline entries
  (`ntf mutation --strict --verify-baseline`), so the suite is run once
  rather than once per target to map its coverage. Locally prefer the two
  narrower targets; run this only to reproduce a CI failure
- `make doc` — after changing the CLI, the test API, or one of the enumerations
  the documents spell out: the operators (`core/mutation/operators.lua`), the
  report labels (`core/mutation/report.lua`), or the config sections and their
  entry fields (`core/mutation/config.lua`). It regenerates `README.md` and
  `doc/ntf.txt`, and fails once the names it spells and the ones the
  implementation works from have parted ways
- `make doc_ci` — what CI runs in place of the above, in the same job as the
  other gates: it regenerates the documents and then fails on any difference
  from the committed `README.md` and `doc/ntf.txt`, so a change that skipped
  `make doc` is answered by CI instead of waiting for the next regeneration.
  Its generation reads genvdoc from the workflow's own packages, so it needs no
  plugin of yours to be installed

## Conventions

- Test API is explicit, never global:
  `local describe, it = require("ntf").describe, require("ntf").it`. Do not inject globals.
- The CLI is a command tree defined once in `lua/ntf/core/controller/args.lua`
  (`M.root`): each command names the flags it accepts, so a flag that means
  nothing to a command is rejected there instead of being checked for after
  parsing. `usage()` and the docs derive from the tree — do not duplicate either
  list. A command's `positional` names what its positional arguments are — spec
  paths for every command that reaches the tests, and nothing at all for one that
  does not (`mutation baseline add`), which then rejects a path instead of
  discovering specs it never runs; only leading tokens name a command.
- `README.md` and `doc/ntf.txt` are generated from `spec/lua/ntf/doc.lua`. Edit
  that, then `make doc`; never hand-edit the outputs. Only the root command's
  usage is shown — a dump of every command's is bulk rather than help — so what
  the prose names is checked instead: every `--flag` in the outputs has to be one
  the command tree takes.
- A documented enumeration keeps its names in `lua/` and its prose in
  `spec/lua/ntf/doc.lua`, which asserts the two name lists are equal — so a name
  the implementation gains, not only one it loses, fails `make doc` until its
  line is written. The engine layer carries no text written for a reader of the
  manual; `operators.lua` keeps its `example` only because `operators_spec.lua`
  runs the enumerator against it. Where the program itself prints the text — the
  flag descriptions `usage()` writes — it stays in `lua/`.
- `WORKFLOW_DIR` names the directory the shared makefile, its scripts and its
  configs are read from. It defaults to `spec/.shared/`, which `make` clones from
  notomo/workflow (gitignored) on first run, and can instead name a local
  workflow checkout: `make test WORKFLOW_DIR=../workflow` (or export it, which is
  the local setup — the clone is then absent and the deps live under the
  checkout's own `packages/`). `$WORKFLOW_DIR` below stands for whichever it is.
- Express structure with LuaCATS (`@class/@field/@param/@return/@type`). Comments
  follow `$WORKFLOW_DIR/script/comment_lint.md`, which `make comment_lint`
  enforces — read it before writing one. Its `WHY:`/`NOT:` pair in practice: see
  `driver.lua` on SIGKILL vs `vim.system`'s SIGTERM, or `mutation/splice.lua` on
  its own module vs part of operators. Outside that rule's `lua/` scope, keep the
  comments genvdoc extracts (e.g. `coverage/highlight_group.lua`) and the ones in
  the snippets `spec/lua/ntf/doc.lua` renders.
- Every code/command element in the generated docs must be backed by something
  `spec/lua/ntf/doc.lua` executes during `make doc` (runnable snippet files in
  `spec/lua/ntf/doc/`, commands assembled from verified runs); no unverified
  snippets.
