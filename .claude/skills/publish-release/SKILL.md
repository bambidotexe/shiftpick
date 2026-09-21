---
name: publish-release
description: Use when the owner asks to publish, release, or ship ShiftPick, to push a release to GitHub, to cut a version, or to make a build available for download. This is one of only two ways a build of this app ever reaches a Mac; the other is install-locally. Use it whenever a GitHub release is involved, including deciding what version to release.
---

# Publish a release

**This app reaches a Mac in exactly two ways.** This skill is the second: the same production build as
`install-locally`, tagged, pushed, attached to a GitHub release — **and installed in `/Applications` too**,
so this Mac runs what was just published.

```bash
make release
# or directly:
sh scripts/publish.sh
```

It takes a few minutes, most of it Apple's notary service. It publishes; that is the point. **Only run it
when the owner has asked for a release.** The update check is anonymous, so **the repository has to be
public for a release to be visible to it**: a private one reads exactly like no release at all.

## Before the first release, the owner has to provide

These are the only things this repository cannot supply itself. All of them are named in `MORNING.md` too.

| What | Where it goes | How to tell it is missing |
|---|---|---|
| A **GitHub repository** at `bambidotexe/shiftpick`, **public**, with `origin` set | `scripts/signing.env` already names it; `git remote add origin …` | `version_published` answers `0.0.0` for ever and every check says *No release published yet* |
| A **Developer ID Application** certificate for team `85F6AC5QZF` in the keychain | the keychain; only the Wooflab Account Holder can create it | `scripts/release.sh` refuses before it builds anything |
| A **notarytool keychain profile** called `wooflab-notary` | `xcrun notarytool store-credentials wooflab-notary --key <AuthKey_XXXX.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>` | the same |

Nothing else is a placeholder. There is no secret in the repository and none is needed at build time.

## What it does, in order

1. **Refuses on a dirty tree, an existing tag, or a `HEAD` that differs from `origin`.** A release names a
   commit, so the commit must exist, be pushed, and be the one you mean. All three refusals come *before*
   the build, because none is worth several minutes of notarizing to discover.
2. **Checks the version rule** (`scripts/version.sh`): the tree is one patch ahead of the newest release, so
   the tree's version is the one being published.
3. **Builds the real thing** (`scripts/release.sh`) — Developer ID, Hardened Runtime, notarized, stapled, in
   its disk image, with Gatekeeper asked about both. The same bytes for GitHub and for `/Applications`.
4. **Tags and pushes**, then creates the GitHub release with the disk image attached. The tag is made only
   once there is an image to attach to it.
5. **Installs it in `/Applications`**, by the same steps as `scripts/install.sh`: stop the running copy and
   wait for it, write the quiet-launch marker, `ditto` the bundle out of the image, verify its signature,
   its version and its ticket, open it. See the `install-locally` skill for why each of those is not
   optional.
6. **Raises the tree to the next patch**, so it is one ahead of what is now published. **That change is left
   uncommitted on purpose — commit it.**
7. **Leaves nothing behind**: no `.app`, no `.dmg` under the repository, on every exit path.

## Publishing without installing

`--no-install` skips step 5: the release is published and `/Applications` keeps the version it is running,
which is then the version that finds the release, fetches it and installs it itself. It is the only way to
walk the path a user walks, so it is how an update is tested before anyone relies on it.

```bash
sh scripts/publish.sh --no-install
```

## Afterwards

The version bump in step 6 is left in the working tree so the owner sees it. Commit it, conventional
commits like the rest of this repository:

```
build(version): the tree moves to <next>
```

Then check the release page the script printed, and confirm the installed copy is the new one:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/ShiftPick.app/Contents/Info.plist
pgrep -lx ShiftPick
```

And **Shift-click two icons**. Nothing in the publish path exercises what the app does.

## The version rule, and why publishing is the only thing that moves it

The tree is **always one patch ahead of the newest GitHub release**. Publishing is what makes the tree's
version the published one, and the script then raises the tree again. Nothing else changes the version: not
a feature, not a fix, not a local install.

That rule is what keeps this Mac's copy from ever being offered a downgrade.

## Never do these

| Never | Instead |
|---|---|
| Publish without the owner asking | A release is public and cannot be quietly undone |
| Hand-run `gh release create` | `scripts/publish.sh`, which builds, notarizes, tags, publishes, installs and cleans up in the right order |
| Tag before there is an image | The script tags after the build for exactly this reason |
| Attach anything but the notarized image | The update check requires a `.dmg` asset with `ShiftPick.app` at the image's root |
| Set the version by hand | `version_set` in `scripts/version.sh` is the only place that writes it |
| Leave a built bundle behind | Spotlight will offer it, and it will run beside `/Applications` with a second event tap on the same clicks |

## If it fails part way

- **Before the tag**: nothing was published. Fix and run it again.
- **After the tag, before the release**: the tag is pushed. Either `gh release create` it by hand with the
  image, or delete the tag locally and on `origin` and start over.
- **After the release, before the install finishes**: the release exists but `/Applications` may still hold
  the old copy. Run `make install` — it repeats the same steps against the already-published version.
- **After the release**: the release exists. Deleting it is the owner's call, not yours — say what happened
  and let them decide.
