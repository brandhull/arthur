# Versioning

Arthur uses [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.
One version covers all three targets (Arthur-Mac, Arthur-iOS, ArthurBar) —
they ship together and share ArthurKit.

| Bump | When | Examples |
|---|---|---|
| **PATCH** `1.0.x` | Bug fixes, copy/layout tweaks, small polish. No new capability. | The Rocks save fix; a stale error message that never cleared |
| **MINOR** `1.x.0` | A new feature or a visible behavior change. | Numbered-list indent in the editor; Search Craft; a new tab |
| **MAJOR** `x.0.0` | A redesign, or a change that breaks stored data/settings and needs migrating. | The Mac sidebar redesign; a Config format change |

Rules of thumb:

- Several fixes can ship in one patch. Don't bump per commit.
- When a release mixes a fix and a feature, the bigger one wins (minor).
- Majors are rare. Many minors between majors is normal.
- Resetting: a minor bump zeroes the patch (`1.2.3` → `1.3.0`); a major bump
  zeroes both (`1.3.0` → `2.0.0`).

## The build number

Separate from the version. It is the git commit count at build time
(`git rev-list --count HEAD`), stamped into `CFBundleVersion` by a post-build
script on each target (see `project.yml`). It rises automatically, which is
what App Store Connect / TestFlight needs to be unique per upload. Settings
(and ArthurBar's menu) show it as `1.0.0 (66)`, so you can tell exactly which
build is installed on a device.

## Cutting a release

1. Move the `[Unreleased]` entries in `CHANGELOG.md` under a new
   `## [x.y.z] - YYYY-MM-DD` heading.
2. Set `MARKETING_VERSION` in `project.yml` (the top-level `settings.base`).
3. `xcodegen generate` — then, per SCOPE.md, check each target's Team is
   still set in Xcode before an on-device run.
4. Commit: `Release x.y.z`.
5. Tag that commit: `git tag -a vx.y.z -m "Arthur x.y.z"` (and `git push --tags`
   when a remote exists).
6. Build and install.
