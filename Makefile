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
# leaving nothing launchable behind. scripts/install.sh has the sequence and why each step is not optional.
install:
	sh scripts/install.sh

# The same install, plus a tagged, pushed GitHub release carrying the disk image. Only run when the owner
# has asked for a release. scripts/publish.sh has the sequence.
release:
	sh scripts/publish.sh

# What the Finder cannot do: the login item and the Accessibility grant are registrations, not files.
# Settings > General > Uninstall is the supported way and removes the preferences too.
uninstall:
	-killall ShiftPick 2>/dev/null
	rm -rf "$(DEST)"
	@echo "Settings > General > Uninstall is the way that also gives back the Accessibility permission,"
	@echo "removes the Login Items entry and removes the preferences. This target leaves all three behind."
