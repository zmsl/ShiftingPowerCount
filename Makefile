# Shifting Power Count. `make bootstrap` once, then `make check` before a push.
LUA_ENV := .lua
LUACHECK := $(LUA_ENV)/bin/luacheck
BUSTED := $(LUA_ENV)/bin/busted
LUAC := $(if $(wildcard $(LUA_ENV)/bin/luac),$(LUA_ENV)/bin/luac,luac5.1)
# BigWigs packager, pinned like Hekili Forever's release workflow (v2.6.1).
PACKAGER_REF := e50a250f8705041e40f2fa1ddcb280a686d65aa0

.PHONY: bootstrap lint syntax test tools-test check package package-check

bootstrap:
	scripts/bootstrap.sh
lint:
	$(LUACHECK) -q .
syntax:
	git ls-files -z '*.lua' | xargs -0 $(LUAC) -p
test:
	$(BUSTED) spec
tools-test:
	python3 -I tools/test_cf_upload.py
check: lint syntax test tools-test
package:
	@mkdir -p $(LUA_ENV)
	@test -s $(LUA_ENV)/release-$(PACKAGER_REF).sh || curl -fsSL https://raw.githubusercontent.com/BigWigsMods/packager/$(PACKAGER_REF)/release.sh -o $(LUA_ENV)/release-$(PACKAGER_REF).sh
	bash $(LUA_ENV)/release-$(PACKAGER_REF).sh -d -r $(CURDIR)/.release
package-check: package
	bash tools/check_package.sh "$$(ls -t .release/ShiftingPowerCount-*.zip | head -1)"
