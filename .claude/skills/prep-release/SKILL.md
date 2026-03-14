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


### 2. Bump the version

Update **every** `MARKETING_VERSION = ...;` line in
`Mud.xcodeproj/project.pbxproj` to the new version. There are multiple
occurrences (one per build configuration) — update them all.


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


### 4. Hand off

Tell the user what remains for them to do:

1. Review and edit `Doc/RELEASES.md` if needed.
2. Run `.github/scripts/build-release-notes` to render the HTML.
3. Commit with message: `VERSION: X.Y.Z.`
4. Merge to `main`, tag as `vX.Y.Z`, and push to trigger the release workflow.
