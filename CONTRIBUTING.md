# Contributing to YTLiteSkipSilence

Thanks for your interest! PRs welcome.

## Development setup

1. Install [Theos](https://theos.dev) on a Mac or Linux machine.
2. Clone this repo and the vendor headers as siblings:

   ```sh
   git clone https://github.com/<you>/YTLiteSkipSilence.git
   git clone https://github.com/PoomSmart/YouTubeHeader.git
   git clone https://github.com/PoomSmart/PSHeader.git
   git clone https://github.com/PoomSmart/YTVideoOverlay.git
   ```

3. Build:
   ```sh
   cd YTLiteSkipSilence
   make clean package FINALPACKAGE=1     # classic
   make clean package FINALPACKAGE=1 ROOTLESS=1   # rootless
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

## Coding style

- ARC is required (`-fobjc-arc`).
- The audio render callback (`tapProcess`) is on the audio thread: **no allocations, no locks, no `@autoreleasepool`**.
- All state mutation in the manager goes through `@synchronized(self)`.
- No new third-party dependencies without discussion.

## Testing

- Test on YouTube 19.x and 20.x.
- Test with podcasts, lectures, music videos, silent intro / outro videos.
- Verify the toggle button shows in both top and bottom positions.
- Verify `MTAudioProcessingTap` is correctly released when navigating between videos (Instruments → Leaks).

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
