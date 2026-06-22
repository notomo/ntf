include spec/.shared/neovim-plugin.mk

spec/.shared/neovim-plugin.mk:
	git clone https://github.com/notomo/workflow.git --depth 1 spec/.shared

# override: ntf tests itself with itself instead of vusted
REQUIREALL_IGNORE_MODULES=ntf.core.worker
ifeq ($(OS),Windows_NT)
test: requireall FORCE
	bin\ntf.bat --shuffle
else
test: requireall FORCE
	./bin/ntf --shuffle
endif
