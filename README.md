# YTLiteSkipSilence

> Overcast-style **Skip Silence** for the YouTube iOS app, built as a
> [YTLite](https://github.com/dayanch96/YTLite)-compatible Theos tweak and
> wired up with a clean toggle button via
> [YTVideoOverlay](https://github.com/PoomSmart/YTVideoOverlay).

## What it does

When you're watching YouTube videos with quiet patches — long intro silence,
dead air between sentences, podcast-style episodes mirrored to YouTube —
**YTLiteSkipSilence** dynamically speeds up those silent regions (default
**2.5×**) and instantly restores your normal speed the moment audio returns.

The audio pipeline is monitored in real time via `MTAudioProcessingTap`,
the rolling RMS is compared against a dBFS threshold (default −35), and when
the level stays below the threshold for longer than a hold-time (default
150 ms), the playback rate is bumped up. When the level rises back above
the threshold for longer than a release-time (default 40 ms), the rate is
restored to whatever YouTube (or you) last set.

## How it works

```
┌──────────────────────────── YouTube process ─────────────────────────────┐
│                                                                          │
│   YouTube AVPlayer ─ owns ─> AVPlayerItem ─ owns ─> AVAsset              │
│                                      │                                   │
│                                      ▼                                   │
│           ┌──────────────────────────────────────────────┐               │
│           │  MTAudioProcessingTap  (MediaToolbox)         │               │
│           │   process() callback fires per audio render   │               │
│           │   cycle with an AudioBufferList of Float32    │               │
│           │   PCM samples.                                │               │
│           └──────────────────────────────────────────────┘               │
│                                      │                                   │
│                                      ▼                                   │
│           ┌──────────────────────────────────────────────┐               │
│           │  SkipSilenceManager                          │               │
│           │   • RMS → dBFS                               │               │
│           │   • hysteresis state machine                 │               │
│           │     (holdTime 150 ms / releaseTime 40 ms)    │               │
│           │   • sets AVPlayer.rate when crossing         │               │
│           │     silence boundaries                       │               │
│           └──────────────────────────────────────────────┘               │
│                                      │                                   │
│                                      ▼                                   │
│           AVPlayer.rate = 2.5  (silent region)                           │
│           AVPlayer.rate = 1.0  (loud region, user's chosen rate)         │
└──────────────────────────────────────────────────────────────────────────┘
```

### Why `MTAudioProcessingTap` instead of `AVAudioEngine`?

YouTube's `AVPlayer` is not wired through an `AVAudioEngine` we can reach
reliably. `MTAudioProcessingTap` is the **only** Apple-sanctioned way to
inspect/modify an `AVPlayer`'s audio without re-hosting playback. It runs
on the audio render thread, so the callback is allocation-free.

## Installation

### Requirements

- Jailbroken iOS 13+ device (palera1n, Dopamine, unc0ver, checkra1n —
  rootless or roothide all work) **or** a sideloaded YouTube (TrollStore,
  AltStore) with the tweak injected via `pyzule-rw` / cyan.
- [Theos](https://theos.dev) installed.
- `com.ps.ytvideooverlay` (>= 2.0.0) installed from
  PoomSmart's repo: `https://poomsmart.github.io/repo/`

### Build (local)

```sh
git clone https://github.com/<you>/YTLiteSkipSilence.git
cd YTLiteSkipSilence

# Vendor headers are optional — the tweak uses runtime discovery.
# But for richer type info you may clone them as siblings:
git clone --depth=1 https://github.com/PoomSmart/YouTubeHeader.git
git clone --depth=1 https://github.com/PoomSmart/PSHeader.git

# Install iPhoneOS16.5 SDK into $THEOS/sdks/
curl -L -o /tmp/sdk.tar.xz \
  "https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS16.5.sdk.tar.xz"
mkdir -p "$THEOS/sdks"
tar -xf /tmp/sdk.tar.xz -C "$THEOS/sdks"

# Build
make clean package FINALPACKAGE=1            # classic
make clean package FINALPACKAGE=1 ROOTLESS=1 # rootless
make clean package FINALPACKAGE=1 ROOTHIDE=1 # roothide
```

The `.deb` lands in `packages/com.dvntm.ytlite.skipsilence_*.deb`.

### CI build

This repo includes a GitHub Actions workflow (`.github/workflows/build.yml`)
that builds all three schemes (classic, rootless, roothide) on every push.
The workflow:

1. Checks out Theos.
2. Downloads the iPhoneOS16.5 SDK from `theos/sdks` tagged release.
3. Clones YouTubeHeader + PSHeader into `$THEOS/include/vendor/`.
4. Runs `make clean package FINALPACKAGE=1`.

## Configuration

### The toggle button (default — bottom player bar)

A speaker icon appears in the bottom player bar (next to the fullscreen
button). Tap to enable/disable; the icon swaps between `speaker.slash.fill`
(off) and `speaker.wave.3.fill` (on).

In YouTube's settings, under **YTVideoOverlay** → **Skip Silence**, you can:

- Move the button between Top and Bottom rows.
- Toggle the master on/off.
- Reorder relative to other YTVideoOverlay buttons.

### YouTube's in-app Settings → "Skip Silence" section

A new section (ID 790) is injected into YouTube's own settings UI:

- Master on/off switch
- Show Time-Saved Toast on/off
- Time-saved readout
- Current threshold & speed display

Advanced tunables (threshold, speed, hold time, release time) can be set
via `NSUserDefaults` suite `com.dvntm.ytlite.skipsilence`:

```objc
NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:@"com.dvntm.ytlite.skipsilence"];
[d setFloat:-40.0f forKey:@"skipSilenceThresholdDBFS"];  // -25..-45 dBFS
[d setFloat:3.0f  forKey:@"skipSilenceSilenceRate"];     // 1.5..4.0
[d setFloat:0.20f forKey:@"skipSilenceHoldTime"];        // seconds
[d setFloat:0.08f forKey:@"skipSilenceReleaseTime"];     // seconds
```

## Tuning recommendations

| Setting | Default | When to change |
|---|---|---|
| Threshold | −35 dBFS | Lower (−40, −45) for very dynamic speech; higher (−25, −30) for noisy background music. |
| Silence speed | 2.5× | Lower (1.5×, 2.0×) if 2.5× feels jarring; higher (3.0×, 4.0×) for power-watching lectures. |
| Hold time | 150 ms | Lower (80–100 ms) for snappier skipping; higher (200–300 ms) to preserve natural pauses. |
| Release time | 40 ms | Higher (80–120 ms) if you hear "stutter" at the start of sentences. |

## File layout

```
YTLiteSkipSilence/
├── Makefile                         # Theos build
├── control                          # Debian package metadata
├── YTLiteSkipSilence.plist          # MobileSubstrate filter
├── YTLiteSkipSilence.x              # Main tweak: YTVideoOverlay button + AVPlayer hooks
├── Settings.x                       # In-app settings section (ID 790)
├── Utils/
│   ├── SkipSilenceManager.{h,m}     # MTAudioProcessingTap engine + state machine
│   ├── SkipSilenceDefaults.{h,m}    # NSUserDefaults wrapper
│   ├── NSBundle+YTSkipSilence.{h,m} # Bundle resolution
│   └── Reachability.{h,m}           # Reachability (kept for parity)
├── Resources/
│   ├── depiction.json               # Sileo depiction
│   └── YTLiteSkipSilence.bundle/
│       ├── Info.plist
│       ├── skipsilence_on*.png      # Toggle button icons (1x/2x/3x)
│       ├── skipsilence_off*.png
│       └── en.lproj/Localizable.strings
├── .github/workflows/build.yml      # CI build
├── README.md
├── LICENSE                          # MIT
├── CHANGELOG.md
├── CONTRIBUTING.md
└── .gitignore
```

## Compatibility

| Component | Version |
|---|---|
| YouTube | 19.x – 20.x (any version YTLite currently supports) |
| iOS | 13.0+ |
| YTVideoOverlay | 2.0.0+ |
| Theos | latest |
| Architecture | arm64, arm64e |

## Acknowledgements

- **[Overcast](https://overcast.fm)** by Marco Arment — original Smart Speed
  algorithm; the `OCVoiceBoostLookahead.c` look-ahead pattern inspired this
  tweak's hysteresis model. Behavioural reference only; no code copied.
- **[YTLite](https://github.com/dayanch96/YTLite)** by dayanch96 / dvntm —
  the host tweak whose project layout and settings-injection pattern this
  tweak mirrors.
- **[YTVideoOverlay](https://github.com/PoomSmart/YTVideoOverlay)** by
  PoomSmart — the button-hosting framework this tweak registers with.
- **[YouTubeHeader](https://github.com/PoomSmart/YouTubeHeader)** and
  **[PSHeader](https://github.com/PoomSmart/PSHeader)** by PoomSmart — the
  YouTube class headers (optional at build time; we use runtime discovery).

## License

MIT. See [LICENSE](LICENSE).
