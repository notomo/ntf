DEPS_SKIP_NTF=1

ifeq ($(OS),Windows_NT)
NTF=bin\ntf.bat
else
NTF=./bin/ntf
endif

REQUIRE_LINT_CONFIG=spec/require_lint.json
CI_TARGETS=require_lint comment_lint requireall mutation_ci

include spec/.shared/neovim-plugin.mk

spec/.shared/neovim-plugin.mk:
	git clone https://github.com/notomo/workflow.git --depth 1 spec/.shared

REQUIREALL_IGNORE_MODULES=ntf.core.worker

MUTATION_TARGETS=mutation mutation_list mutation_verify_baseline mutation_ci

$(MUTATION_TARGETS): MUTATION_FLAGS += --mutation-config=spec/mutation.json

mutation: MUTATION_FLAGS += --mutation-strict

# mutation_verify_baseline re-runs the baseline entries alone
# (--mutation-verify-baseline=only) and fails any a test can now kill. Kept out
# of the mutation gate to spare its hot path.
mutation_verify_baseline: MUTATION_FLAGS += --mutation-verify-baseline=only
mutation_verify_baseline: FORCE deps
	$(NTF) ${MUTATION_FLAGS} ${EXCLUDE_CODE_FLAGS} ${SPEC_DIR}

# mutation_ci is what CI runs in place of mutation and mutation_verify_baseline:
# one pass scores the mutants and re-runs the baseline entries, sparing the
# second run of the whole suite the two targets each need to map its coverage.
mutation_ci: MUTATION_FLAGS += --mutation-strict --mutation-verify-baseline
mutation_ci: FORCE deps
	$(NTF) ${MUTATION_FLAGS} ${EXCLUDE_CODE_FLAGS} ${SPEC_DIR}
