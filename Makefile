DEPS_SKIP_NTF=1

ifeq ($(OS),Windows_NT)
NTF=bin\ntf.bat
else
NTF=./bin/ntf
endif

REQUIRE_LINT_CONFIG=spec/require_lint.json
CI_TARGETS=mutation require_lint comment_lint

include spec/.shared/neovim-plugin.mk

spec/.shared/neovim-plugin.mk:
	git clone https://github.com/notomo/workflow.git --depth 1 spec/.shared

REQUIREALL_IGNORE_MODULES=ntf.core.worker

# Excluded rather than mutated, because ntf is self-hosted: mutants in the
# process-spawning and worker machinery hang (burning trial timeouts) or fail
# every test for infrastructure reasons — kills that measure nothing about the
# specs. The editor-facing and formatting layers are left out to keep the run
# focused on the pure logic with direct unit specs.
mutation mutation_list: EXCLUDE_CODE += \
	lua/ntf/init.lua \
	lua/ntf/helper.lua \
	lua/ntf/coverage \
	lua/ntf/mutation \
	lua/ntf/core/hook.lua \
	lua/ntf/core/runtime.lua \
	lua/ntf/core/worker/driver.lua \
	lua/ntf/core/worker/init.lua \
	lua/ntf/core/worker/executor.lua \
	lua/ntf/core/mutation/runner.lua \
	lua/ntf/core/mutation/init.lua \
	lua/ntf/core/mutation/report.lua \
	lua/ntf/core/coverage/report.lua \
	lua/ntf/core/controller/init.lua \
	lua/ntf/core/controller/pool.lua \
	lua/ntf/core/controller/progress.lua \
	lua/ntf/core/controller/report.lua \
	lua/ntf/core/controller/discover.lua \
	lua/ntf/core/controller/work.lua

# Every spec except init_spec.lua rather than the whole suite: its bin/ntf
# end-to-end tests spawn a nested nvim per test and would dominate the
# mutation run's cost.
SPEC_ROOT = spec/lua/${PLUGIN_NAME}
# Subdirectories come from $(dir) over their entries rather than a ${SPEC_ROOT}/*/
# glob, because make 3.81 (macOS) and mingw make strip the trailing slash and so
# match plain files such as doc.lua too, which ntf rejects as not a spec file.
SPEC_SUBDIRS = $(sort $(dir $(wildcard ${SPEC_ROOT}/*/*)))
mutation mutation_list: SPEC_DIR = $(filter-out ${SPEC_ROOT}/init_spec.lua,$(wildcard ${SPEC_ROOT}/*_spec.lua) ${SPEC_SUBDIRS})

MUTATION_FLAGS += --mutation-baseline=spec/mutation_baseline.json --mutation-strict
