# Plezy custom Windows builds

This branch holds no app code. It holds the automation that rebuilds every
[upstream Plezy](https://github.com/edde746/plezy) release for Windows with this
fork's patches on top, and publishes the result as a release of this fork.

## How it works

`.github/workflows/custom-windows-release.yml` runs daily and on demand:

1. `scripts/plan.sh` finds the latest upstream release and fingerprints it
   together with the current head of every branch in `patches.txt`. If a
   release of this fork already carries that fingerprint, the run stops.
2. `scripts/compose.sh` cherry-picks each patch branch onto the upstream tag
   and exports the result as a patch series. A conflict that touches only
   generated translations keeps upstream's copy, and the build regenerates
   them with slang. Any other conflict fails the run.
3. The build jobs apply the series to the upstream tag and build x64 and arm64
   with the same steps upstream uses, then the installer is signed for
   WinSparkle with the `SPARKLE_PRIVATE_KEY` secret.
4. The release job publishes `<version>-r<revision>` as the latest release,
   with the installer and an `appcast.xml`.

## Updates

The `fork/updater` patch points installed apps at
`https://github.com/<fork>/releases/latest/download/appcast.xml` and embeds the
public half of `SPARKLE_PRIVATE_KEY`, so installs update from this fork only.
Losing that private key means existing installs can no longer verify updates.

WinSparkle compares the 16-bit build number of the executable. Each fork
revision of upstream build `N` is built as `N * 10 + revision`, which leaves
ten revisions per upstream release.

## Maintenance

- A run that fails on a conflict means a patch branch needs rebasing onto
  upstream `main`. Rebase it, push it, and run the workflow again.
- When upstream ships one of the patches, remove its branch from
  `patches.txt`.
- The build steps mirror upstream's `build-windows` and `package-windows`
  jobs. Compare them when upstream changes how Windows is built.
