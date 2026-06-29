# Contributing to YTLiteSkipSilence

Thanks for your interest! PRs welcome.

## Development setup

1. Install [Theos](https://theos.dev) on a Mac or Linux machine.
2. Clone this repo and (optionally) the vendor headers as siblings:

   ```sh
   git clone https://github.com/<you>/YTLiteSkipSilence.git
   cd YTLiteSkipSilence
   git clone --depth=1 https://github.com/PoomSmart/YouTubeHeader.git
   git clone --depth=1 https://github.com/PoomSmart/PSHeader.git
   ```

3. Install the iPhoneOS16.5 SDK:

   ```sh
   curl -L -o /tmp/sdk.tar.xz \
     "https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS16.5.sdk.tar.xz"
   mkdir -p "$THEOS/sdks"
   tar -xf /tmp/sdk.tar.xz -C "$THEOS/sdks"
   ```

4. Build:

   ```sh
   make clean package FINALPACKAGE=1            # classic
   make clean package FINALPACKAGE=1 ROOTLESS=1 # rootless
   ```

## Where to make changes

| Change | File |
|---|---|
| Silence detector algorithm | `Utils/SkipSilenceManager.m` |
| Settings keys / defaults | `Utils/SkipSilenceDefaults.{h,m}` |
| Toggle button UI | `YTLiteSkipSilence.x` (groups `Top` / `Bottom`) |
| Settings pane in YouTube | `Settings.x` |
| Bundle resolution (paths) | `Utils/NSBundle+YTSkipSilence.m` |
| Build flags | `Makefile` |
| CI workflow | `.github/workflows/build.yml` |

## Coding style

- ARC is required (`-fobjc-arc`).
- The audio render callback (`tapProcess`) is on the audio thread: **no
  allocations, no locks, no `@autoreleasepool`**.
- All state mutation in the manager goes through `@synchronized(self)`.
- No new third-party dependencies without discussion.
- The tweak must build without vendor headers checked out (use runtime
  discovery via `NSClassFromString` / `NSSelectorFromString`).

## Testing

- Test on YouTube 19.x and 20.x.
- Test with podcasts, lectures, music videos, silent intro / outro videos.
- Verify the toggle button shows in both top and bottom positions.
- Verify `MTAudioProcessingTap` is correctly released when navigating between
  videos (Instruments → Leaks).

## Commit style

Conventional Commits preferred:

```
feat: add threshold picker to settings
fix: detach tap when video changes mid-playback
docs: clarify MTAudioProcessingTap lifecycle
```

## Releasing

1. Bump `PACKAGE_VERSION` in `Makefile` and `Version` in `control`.
2. Tag `vX.Y.Z`.
3. CI builds and uploads `.deb`s to the GitHub release.
