# ntf

Dependency-free neovim test CLI. Self-hosted: ntf runs its own specs.

## Gates (run before finishing any change)

- `make test` — specs pass (ntf runs itself)
- `make check` — lua-language-server reports no problems
  (set `CHECK_VIMRUNTIME` to your nvim runtime dir if it is not at the default)
- `stylua --config-path spec/.shared/stylua.toml lua spec/lua bin/ntf` — no diff
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
