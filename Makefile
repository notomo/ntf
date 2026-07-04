DEPS_SKIP_NTF=1

include spec/.shared/neovim-plugin.mk

spec/.shared/neovim-plugin.mk:
	git clone https://github.com/notomo/workflow.git --depth 1 spec/.shared

REQUIREALL_IGNORE_MODULES=ntf.core.worker
ifeq ($(OS),Windows_NT)
test: requireall FORCE
	bin\ntf.bat --shuffle
coverage: deps FORCE
	bin\ntf.bat --coverage=spec\.shared\luacov.stats.out
else
test: requireall FORCE
	./bin/ntf --shuffle
coverage: deps FORCE
	./bin/ntf --coverage=spec/.shared/luacov.stats.out
endif
