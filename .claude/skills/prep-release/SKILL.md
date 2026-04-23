---
name: prep-release
description: Prepare a new Mud release — bump version and draft release notes.
disable-model-invocation: true
argument-hint: <version>
---

Prepare a release for Mud
===============================================================================

The user has invoked `/prep-release $ARGUMENTS`.

The argument is the new version number (e.g. `1.3.0`). If no argument was
provided, ask for the version number before proceeding.


## Steps

### 1. Validate

- Confirm the argument looks like a version number (X.Y.Z).
- Read `Mud.xcodeproj/project.pbxproj` and find the current
  `MARKETING_VERSION`. Confirm the new version is higher.
- Check `Doc/RELEASES.md` to make sure a section for this version doesn't
  already exist.

If any check fails, stop and explain.


### 2. Bump the versions

Run `.github/scripts/prep-release-version X.Y.Z` from the project root. The
script updates `MARKETING_VERSION` across every build configuration in the
pbxproj and increments `CURRENT_PROJECT_VERSION` by one across every build
configuration. App Store and Direct distribution share a single monotonic
`CFBundleVersion` stream — Sparkle compares the new value against the installed
app's `CFBundleVersion` to decide whether to offer an update — so the build bump
runs unconditionally regardless of channel.

The script validates state before writing (version format, pbxproj presence,
consistent current values, new marketing version strictly higher than the
old). If any precondition fails, it exits non-zero with a message; surface the
failure and stop.

After a successful run, verify the diff touches only the pbxproj and only the
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` lines.


### 3. Draft release notes

Gather context for writing release notes:

- Run `git log --oneline` from the last version tag to HEAD.
- Read any recent plan files in `Doc/Plans/` that are marked Underway or
  recently completed.

Then draft a new section for `Doc/RELEASES.md`. Follow the existing style:

- Insert the new section at the top, after the `===` heading rule.
- Heading format: `## vX.Y.Z`
- Bulleted list of user-facing changes.
- Concise, compelling prose — these are user-facing notes, not a changelog.
  Lead each bullet with the feature or fix, not the file or module.
- Don't mention internal refactors, code cleanup, or implementation details
  unless they have user-visible impact.
- Omit changes that are only relevant to developers (CI, build scripts, etc).
- Wrap lines at 78 characters.

Present the draft to the user for review. Incorporate any feedback.


### 4. Finalize

Use `AskUserQuestion` to block while the user reviews the notes and renders the
HTML:

- Question: "Review `Doc/RELEASES.md`, then run
  `.github/scripts/build-release-notes` to render the HTML. Continue when
  ready."
- Header: "Finalize"
- Options:

  - `Done` (description: "Notes reviewed and HTML rendered — commit, merge, and
    tag.")
  - `Cancel` (description: "I'll finish the remaining steps by hand.")

**On `Done`**, run these commands in sequence. Stop and surface any error
instead of continuing past it:

```
git add Mud.xcodeproj/project.pbxproj Doc/RELEASES.md Site/releases/
git commit -m "VERSION: X.Y.Z."
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  git checkout main
  git merge --ff-only "$BRANCH"
fi
git tag vX.Y.Z
```

Then tell the user (in chat) that everything local is ready, and to push with:

```
git push origin main vX.Y.Z
```

Do **not** run the push yourself — pushing the tag triggers the release
workflow, which is a shared-state action the user authorizes explicitly.

**On `Cancel`**, instead print the list of remaining steps for the user to
perform:

1. Review and edit `Doc/RELEASES.md` if needed.
2. Run `.github/scripts/build-release-notes` to render the HTML.
3. Commit the bump, notes, and rendered HTML with message `VERSION: X.Y.Z.`.
4. If on a feature branch, merge to `main` (`--ff-only` preferred).
5. Tag as `vX.Y.Z`.
6. Push with `git push origin main vX.Y.Z` to trigger the release workflow.
