# Releasing fiddle

## Prerequisites

- The Release signing config is set in the Xcode project (Developer ID, Team 5JJ6G6A84S, hardened runtime).
- `scripts/.notary-config.local` exists and is filled in (copy `scripts/.notary-config.example`, gitignored, never commit the `.p8` key).
- `gh` is authenticated for the `umzcio/fiddle` repo.

## Steps

1. Bump the version. In Xcode, raise `MARKETING_VERSION` (e.g. `1.0.6`) and `CURRENT_PROJECT_VERSION` (the build number) on the Fiddle target. Commit:
   ```
   git commit -am "bump: 1.0.6 (build 7)"
   ```

2. Run the release script with the new version:
   ```
   scripts/release.sh 1.0.6
   ```
   This now runs, in order: the test suite, build and sign the app, a check that the built app's `CFBundleShortVersionString` actually matches the version you passed in, package the `.dmg`, notarize, staple, repackage the `.dmg` (so the shipped copy carries the staple), notarize and staple again, then regenerate `appcast.xml`.

   The double notarize-and-staple pass is intentional, not a bug. Stapling the `.app` changes its bytes, so the `.dmg` has to be repackaged after the first staple, and the new `.dmg` needs its own notarization ticket.

3. Publish the GitHub release with the built `.dmg`:
   ```
   gh release create v1.0.6 build/Fiddle-1.0.6.dmg --title "fiddle 1.0.6" --notes "..."
   ```

4. Commit and push the regenerated appcast so the Sparkle update feed goes live:
   ```
   git add appcast.xml && git commit -m "appcast: 1.0.6" && git push
   ```

## What the guards catch

- **Red tests.** The script aborts on the first failing test, before anything is built, signed, or shipped.
- **Version drift.** If you run `scripts/release.sh 1.0.6` but forgot to bump `MARKETING_VERSION` (or bumped it and forgot to commit before building), the built app's actual version will not match the `1.0.6` you asked for. The script fails loudly instead of silently shipping a `.dmg` named `1.0.6` that contains a different version, which would otherwise poison the Sparkle feed: the appcast is generated from the built app's real version, so the enclosure URL and the advertised version would disagree.
