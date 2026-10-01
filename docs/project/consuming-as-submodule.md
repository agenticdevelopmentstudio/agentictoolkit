# Consuming the toolkit as a git submodule

For first-party consumers, the toolkit is consumed directly from source
via a git submodule. No separate framework build or SPM publish is
required — the consumer references the in-tree Xcode projects and
rebuilds from source.

## One-time setup in the consumer

Add the submodule wherever you want it to live:

```bash
git submodule add git@github.com:agenticdevelopmentstudio/agentictoolkit.git vendor/agentictoolkit
```

Generate the Apple xcodeproj files so they exist on disk (they are
committed, but it's good practice to run this once to confirm
`project.yml` and `.xcodeproj` are in sync):

```bash
./vendor/agentictoolkit/install.sh
```

In Xcode, add the toolkit workspace (or one of its sub-projects) to your
own workspace:

- **File → Add Files to "<YourWorkspace>"…**
- Pick
  `vendor/agentictoolkit/packages/apple/AgenticToolkit.xcworkspace`
  for the full workspace, or one of:
  - `packages/apple/AgenticToolkit/AgenticToolkit.xcodeproj`
  - `packages/apple/AIPlugins/AIPlugins.xcodeproj`
  - `packages/apple/AgenticToolkitApp/AgenticToolkitApp.xcodeproj`

Then, in your app target's **Frameworks, Libraries, and Embedded
Content** section, add the toolkit framework(s) you want to link against
(e.g. `AgenticToolkitMacOS.framework`).

## Day-to-day workflow

- **Edit toolkit source live.** Branch the submodule
  (`cd vendor/agentictoolkit && git checkout -b feature`), edit any
  `.swift` file under `packages/apple/.../Sources/`, save. Your next
  Xcode build picks it up — no separate install or framework
  re-publish.
- **Commit in two places.** Commit toolkit changes inside the submodule,
  push. Then commit the updated submodule pointer in the consumer repo.
- **Bump in other repos.** In any other consumer:
  `git submodule update --remote vendor/agentictoolkit`. If
  `project.yml` changed, re-run
  `./vendor/agentictoolkit/install.sh`.
- **After editing `project.yml`.** Re-run
  `./vendor/agentictoolkit/install.sh` so the `.xcodeproj` matches the
  new `project.yml`.

## CI / deployment

Enable submodule checkout in your CI platform:

- **GitHub Actions:** `actions/checkout@v4` with `submodules: recursive`.
- **Xcode Cloud:** check "Include submodules" in the workflow source
  settings.

CI runs the consumer's normal `xcodebuild` against its own workspace,
which transitively builds the toolkit sub-projects from source. No
prebuilt toolkit artifact is required.

## Future: tagged-release consumers

External consumers (outside the org) will eventually consume the toolkit
by tag rather than by submodule — either as a Swift Package
(`.package(url: ..., from: "x.y.z")`) or as a distributed XCFramework.
The source layout does not change; only the consumer's package reference
does. The first-party submodule flow continues to work in parallel.
