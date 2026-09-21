---
name: publish-release
description: Use when the owner asks to publish, release, or ship ShiftPick, to push a release to GitHub, to cut a version, or to make a build available for download. This is one of only two ways a build of this app ever reaches a Mac; the other is install-locally. Use it whenever a GitHub release is involved, including deciding what version to release.
---

# Publish a release

**This app reaches a Mac in exactly two ways.** This skill is the second: the same production build as
`install-locally`, tagged, pushed, attached to a GitHub release — **and installed in `/Applications` too**,
so this Mac runs what was just published.

```bash
make release LEVEL=<patch|minor|major>
# or directly:
sh scripts/publish.sh <patch|minor|major>
```

The level is required: `patch` for a fix, `minor` for a new feature, `major` for a breaking change. If the
owner has not said which, ask before running it — this is the one call that names what a release is. It
takes a few minutes, most of it Apple's notary service. It publishes; that is the point. **Only run it
when the owner has asked for a release.** ShiftPick has never actually been published (no GitHub remote is
set — see below), so this skill exists to stay in lockstep with its siblings' mechanism, not because a
release is imminent.

## Before the first release, the owner has to provide

These are the only things this repository cannot supply itself. All of them are named in `MORNING.md` too.

| What | Where it goes | How to tell it is missing |
|---|---|---|
| A **GitHub repository** at `bambidotexe/shiftpick`, **public**, with `origin` set | `scripts/signing.env` already names it; `git remote add origin …` | `git push` and `gh release create` fail outright with no repository to push to |
| A **Developer ID Application** certificate for team `85F6AC5QZF` in the keychain | the keychain; only the Wooflab Account Holder can create it | `scripts/release.sh` refuses before it builds anything |
| A **notarytool keychain profile** called `wooflab-notary` | `xcrun notarytool store-credentials wooflab-notary --key <AuthKey_XXXX.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>` | the same |

Nothing else is a placeholder. There is no secret in the repository and none is needed at build time.

## What it does, in order

1. **Refuses on a dirty tree.** A release names a commit, and the version bump below is about to add one, so
   whatever is already there must be resolved first.
2. **Computes the new version and refuses if that tag already exists**, locally or on GitHub — checked
   *before* the bump, so a collision costs nothing.
3. **Bumps the version by the level given, commits that alone, and pushes it** (`scripts/version.sh`): the
   tree held exactly the last published version until now, so this is the only version change in the whole
   flow. `git push` happens before anything is built, so the commit this script tags always carries the
   version it releases.
4. **Builds the real thing** (`scripts/release.sh`) — Developer ID, Hardened Runtime, notarized, stapled, in
   its disk image, with Gatekeeper asked about both. The same bytes for GitHub and for `/Applications`.
5. **Tags and pushes**, then creates the GitHub release with the disk image attached. The tag is made only
   once there is an image to attach to it.
6. **Installs it in `/Applications`**, by the same steps as `scripts/install.sh`: stop the running copy and
   wait for it, write the quiet-launch marker, `ditto` the bundle out of the image, verify its signature,
   its version and its ticket, open it. See the `install-locally` skill for why each of those is not
   optional.
7. **Leaves nothing behind**: no `.app`, no `.dmg` under the repository, on every exit path.

Nothing bumps the version again afterward. The tree sits at exactly what was just published until the next
`scripts/publish.sh <level>` — a local install (`install-locally`) always carries that same version.

## Publishing without installing

`--no-install` skips step 6: the release is published and `/Applications` keeps the version it is running,
which is then the version that finds the release, fetches it and installs it itself. It is the only way to
walk the path a user walks, so it is how an update is tested before anyone relies on it.

```bash
sh scripts/publish.sh <patch|minor|major> --no-install
```

## Afterwards

Check the release page the script printed, and confirm the installed copy is the new one:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/ShiftPick.app/Contents/Info.plist
pgrep -lx ShiftPick
```

And **Shift-click two icons**. Nothing in the publish path exercises what the app does. Nothing is left to
commit — the version bump was already committed and pushed before the build started.

## The version rule, and why publishing is the only thing that moves it

`scripts/version.sh` holds the version; nothing enforces the tree being ahead of what is published. A local
install always carries exactly the tree's version (see `install-locally`). Publishing is the only thing that
ever changes it: it bumps the tree by the level asked for, commits and pushes that bump, then releases
exactly that version — not a feature, not a fix, not a local install.

## Never do these

| Never | Instead |
|---|---|
| Publish without the owner asking, or guess the level | A release is public and cannot be quietly undone; ask patch/minor/major if it is not obvious |
| Hand-run `gh release create` | `scripts/publish.sh <level>`, which bumps, commits, builds, notarizes, tags, publishes, installs and cleans up in the right order |
| Tag before there is an image | The script tags after the build for exactly this reason |
| Attach anything but the notarized image | The update check requires a `.dmg` asset with `ShiftPick.app` at the image's root |
| Set the version by hand | `version_set` in `scripts/version.sh` is the only place that writes it; the script calls it, never you |
| Leave a built bundle behind | Spotlight will offer it, and it will run beside `/Applications` with a second event tap on the same clicks |

## If it fails part way

- **Before the version-bump commit**: nothing changed. Fix and run it again.
- **After the bump is committed and pushed, before the tag**: the tree already carries the new version.
  Either fix the problem and run `scripts/publish.sh <level>` again — it will bump *again* from here, which
  is wrong — or, more often, just re-tag and release by hand from the commit that is already there
  (`git tag -a v<version> -m "ShiftPick <version>"`, push the tag, `gh release create`).
- **After the tag, before the release**: the tag is pushed. Either `gh release create` it by hand with the
  image, or delete the tag locally and on `origin` and start over.
- **After the release, before the install finishes**: the release exists but `/Applications` may still hold
  the old copy. Run `make install` — it repeats the same steps against the already-published version.
- **After the release**: the release exists. Deleting it is the owner's call, not yours — say what happened
  and let them decide.
