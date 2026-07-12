DEPS_SKIP_NTF=1

include spec/.shared/neovim-plugin.mk

spec/.shared/neovim-plugin.mk:
	git clone https://github.com/notomo/workflow.git --depth 1 spec/.shared

REQUIREALL_IGNORE_MODULES=ntf.core.worker
ifeq ($(OS),Windows_NT)
test: requireall FORCE
	bin\ntf.bat
coverage: deps FORCE
	bin\ntf.bat --coverage=spec\.shared\luacov.stats.out
mutation: deps FORCE
	bin\ntf.bat --mutation=spec\.shared\ntf-mutation.json
else
test: requireall FORCE
	./bin/ntf
coverage: deps FORCE
	./bin/ntf --coverage=spec/.shared/luacov.stats.out
mutation: deps FORCE
	./bin/ntf --mutation --mutation-file=spec/.shared/ntf-mutation.json
endif
