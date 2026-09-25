DEST := /Applications/ShiftPick.app

.PHONY: build test app dmg install release uninstall

build:
	swift build

test:
	swift test

# Ad-hoc unless a Developer ID certificate is in the keychain; refuses an ad-hoc build without DEBUG_OK=1
# (scripts/make-app.sh) — an ad-hoc build is for reading something a signed build will not show, and is
# never installed. `install` and `release` build the real, signed, notarized thing instead.
app:
	sh scripts/make-app.sh

# The disk image a GitHub release carries; it publishes nothing.
dmg:
	sh scripts/make-dmg.sh

# The real, signed, notarized, stapled bundle — never build/ShiftPick.app — replacing /Applications and
# leaving nothing launchable behind. Refuses a tree whose tests fail, and fails when the launch it reads back
# from the app's log is not sound (scripts/safety-gates.sh). scripts/install.sh has the sequence and why
# each step is not optional.
install:
	sh scripts/install.sh

# The same build as install, as a tagged, pushed GitHub release carrying the disk image, at the version the
# given LEVEL bumps to (patch, minor or major — required); NOTES is the file holding the release notes
# (required, outside the repository). Only run when the owner has asked for a release. /Applications is left
# alone unless INSTALL=1 is given, which only the owner asks for. When the safety layer changed since the
# last release it also needs DRILL=walked or DRILL=waived, which only the owner can say
# (docs/manual-test-checklist.md §9). scripts/publish.sh has the sequence.
release:
	sh scripts/publish.sh $(LEVEL) --notes=$(NOTES) $(if $(INSTALL),--install)

# What the Finder cannot do: the login item and the Accessibility grant are registrations, not files.
# Settings > General > Uninstall is the supported way and removes the preferences too.
uninstall:
	-killall ShiftPick 2>/dev/null
	rm -rf "$(DEST)"
	@echo "Settings > General > Uninstall is the way that also gives back the Accessibility permission,"
	@echo "removes the Login Items entry and removes the preferences. This target leaves all three behind."
