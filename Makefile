DEPS_SKIP_NTF=1

ifeq ($(OS),Windows_NT)
NTF=bin\ntf.bat
else
NTF=./bin/ntf
endif

REQUIRE_LINT_CONFIG=spec/require_lint.json
CI_TARGETS=require_lint comment_lint requireall mutation mutation_verify_baseline

include spec/.shared/neovim-plugin.mk

spec/.shared/neovim-plugin.mk:
	git clone https://github.com/notomo/workflow.git --depth 1 spec/.shared

REQUIREALL_IGNORE_MODULES=ntf.core.worker

# mutation_matrix reuses the same self-hosting setup to report which specs never
# solely detect a mutant (--mutation-matrix); it shares mutation's exclusions and
# baseline but not its --mutation-strict gate, since it reports rather than gates.
MUTATION_TARGETS=mutation mutation_list mutation_matrix mutation_verify_baseline

$(MUTATION_TARGETS): MUTATION_FLAGS += --mutation-config=spec/mutation.json

mutation: MUTATION_FLAGS += --mutation-strict

mutation_matrix: MUTATION_FLAGS += --mutation-matrix
mutation_matrix: FORCE deps
	$(NTF) ${MUTATION_FLAGS} ${EXCLUDE_CODE_FLAGS} ${SPEC_DIR}

# mutation_verify_baseline re-runs the baseline entries (--mutation-verify-baseline)
# and fails any a test can now kill. Kept out of the mutation gate to spare its
# hot path; CI runs it as the backstop.
mutation_verify_baseline: MUTATION_FLAGS += --mutation-verify-baseline
mutation_verify_baseline: FORCE deps
	$(NTF) ${MUTATION_FLAGS} ${EXCLUDE_CODE_FLAGS} ${SPEC_DIR}
