# YTLiteSkipSilence

> Overcast-style **Skip Silence** + Voice Boost for the YouTube iOS app,
> built as a [YTLite](https://github.com/dayanch96/YTLite)-compatible Theos tweak
> and wired up with a clean toggle button via [YTVideoOverlay](https://github.com/PoomSmart/YTVideoOverlay).

![License](https://img.shields.io/badge/license-MIT-blue)
![Theos](https://img.shields.io/badge/built%20with-Theos-orange)
![iOS](https://img.shields.io/badge/iOS-13%2B-lightgrey)

## What it does

When you're watching YouTube videos with quiet patches — long intro silence,
dead air between sentences, podcast-style episodes mirrored to YouTube —
**YTLiteSkipSilence** dynamically speeds up those silent regions (default
**2.5×**) and instantly restores your normal speed the moment audio returns.

It's the same idea as Overcast's marquee **Smart Speed** feature: the audio
pipeline is monitored in real time via `MTAudioProcessingTap`, the rolling
RMS is compared against a dBFS threshold, and when the level stays below
that threshold for longer than a hold-time, the playback rate is bumped up
to a configurable "silence rate". When the level rises back above the
threshold for longer than a release-time, the rate is restored to whatever
YouTube (or you) last set.

```
            ┌─────────────────── quiet ───────────────────┐
   loud ────┤                                              ├─── loud ────
            └────────────────── rate × 2.5 ───────────────┘
                  ↑                              ↑
                  holdTime                       releaseTime
                  (150 ms)                       (40 ms)
```

The toggle button is a clean SF-Symbol icon in YouTube's overlay row, placed
wherever you want — top-right controls (`YTMainAppControlsOverlayView`) or
bottom player bar next to fullscreen (`YTInlinePlayerBarContainerView`).
Tap it to toggle on/off; long-press the row in YTVideoOverlay's settings to
move it.

## Why this exists

The Overcast podcast app has had the best-in-class "Smart Speed" silence
skipping since 2014. This tweak brings the same UX to YouTube, where many
podcasts, lectures, and interviews are now mirrored.

This is a **personal-use** reimplementation: the Overcast IPA was used as a
behavioural reference (its `OCAudioStreamer.skipSilences`,
`silenceSkippingSpeed`, `seekToNextSilenceWithMinimumSampleDuration:threshold:`,
`timestampOfNearestSilenceBetweenStartTime:endTime:silenceThreshold:` API
surface confirmed the algorithm design and tunable defaults), but no code
was copied verbatim. The Overcast silence detector is implemented in
`/Users/marco/overcast/overcast-ios/OCAudio/Sources/OCAudioCore/OCVoiceBoost/OCVoiceBoostLookahead.c`
as a look-ahead compressor/limiter; we use the simpler and YouTube-safe
real-time rate-modulation approach documented below.

## How it works

```
┌────────────────────────────── YouTube process ──────────────────────────────┐
│                                                                              │
│   YouTube's AVPlayer ── owns ──> AVPlayerItem ── owns ──> AVAsset            │
│                                          │                                   │
│                                          ▼                                   │
│              ┌──────────────────────────────────────────────┐                │
│              │  MTAudioProcessingTap  (MediaToolbox)         │                │
│              │   tapProcess() callback fires per audio       │                │
│              │   render cycle with an AudioBufferList of     │                │
│              │   Float32 PCM samples.                        │                │
│              └──────────────────────────────────────────────┘                │
│                                          │                                   │
│                                          ▼                                   │
│              ┌──────────────────────────────────────────────┐                │
│              │  SkipSilenceManager                          │                │
│              │   • RMS → dBFS                               │                │
│              │   • hysteresis state machine                 │                │
│              │     (holdTime / releaseTime)                 │                │
│              │   • sets AVPlayer.rate when crossing         │                │
│              │     silence boundaries                       │                │
│              └──────────────────────────────────────────────┘                │
│                                          │                                   │
│                                          ▼                                   │
│              AVPlayer.rate = 2.5  (silent region)                            │
│              AVPlayer.rate = 1.0  (loud region, user's chosen rate)          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Why `MTAudioProcessingTap` instead of `AVAudioEngine`?

YouTube's `AVPlayer` is not wired through an `AVAudioEngine` we can reach
reliably. `MTAudioProcessingTap` is the **only** Apple-sanctioned way to
inspect / modify an `AVPlayer`'s audio without re-hosting playback. It runs
on the audio render thread, so the callback is allocation-free and lock-free.

### Why real-time rate modulation instead of pre-scan + seek?

Overcast pre-scans the file to build a silence map, then seeks over silent
regions. That works for downloaded podcasts but is fragile on YouTube
because:

- YouTube streams adaptive HLS/DASH; you can't cheaply pre-scan the asset.
- Seeks on YouTube's `AVPlayer` fight YouTube's own scrubbing/buffering logic
  and trigger re-buffering — bad UX.
- A real-time approach degrades gracefully: worst case, silence plays a bit
  fast instead of being skipped cleanly.

## Installation

### Requirements

- Jailbroken iOS 13+ device (palera1n, Dopamine, unc0ver, checkra1n, rootless
  or roothide all work) **or** a sideloaded YouTube (TrollStore, AltStore)
  with the tweak injected via `pyzule-rw` / cyan.
- [Theos](https://theos.dev) installed.
- Vendor headers checked out as siblings:
  ```sh
  git clone https://github.com/PoomSmart/YouTubeHeader.git
  git clone https://github.com/PoomSmart/PSHeader.git
  git clone https://github.com/PoomSmart/YTVideoOverlay.git
  ```
- The YouTube IPA you want to patch (the tweak itself is bundle-filtered to
  `com.google.ios.youtube`).

### Build

```sh
git clone https://github.com/<you>/YTLiteSkipSilence.git
cd YTLiteSkipSilence

# Classic jailbreak:
make clean package FINALPACKAGE=1

# Rootless:
make clean package FINALPACKAGE=1 ROOTLESS=1

# RootHide:
make clean package FINALPACKAGE=1 ROOTHIDE=1
```

The `.deb` lands in `packages/com.dvntm.ytlite.skipsilence_*.deb`. Install
via Sileo, Zebra, or `dpkg -i`.

### Sideloaded install

If you're sideloading YouTube (no jailbreak), you need to inject **both**
this tweak's `.dylib` and `YTVideoOverlay.dylib` into the YouTube IPA:

```sh
# 1. Build both tweaks
cd ../YTVideoOverlay && make clean package FINALPACKAGE=1 && cd -
make clean package FINALPACKAGE=1

# 2. Inject both dylibs + bundles into the YouTube IPA
pyzule-rw -i YouTube.ipa \
  -o YouTube-patched.ipa \
  -u com.dvntm.ytlite.skipsilence \
  -u com.ps.ytvideooverlay \
  -t "YTLiteSkipSilence,com.ps.ytvideooverlay"
```

Then sideload `YouTube-patched.ipa` via TrollStore or AltStore.

## Configuration

Two places to configure the tweak:

### 1. The toggle button (default — bottom player bar)

A speaker icon appears in the bottom player bar (next to the fullscreen
button). Tap to enable/disable; the icon swaps between `speaker.slash.fill`
(off) and `speaker.wave.3.fill` (on).

In YouTube's settings, under **YTVideoOverlay** → **Skip Silence**, you can:

- Move the button between Top and Bottom rows.
- Toggle the master on/off.
- Reorder relative to other YTVideoOverlay buttons.

### 2. YouTube's in-app Settings → "Skip Silence" section

YTLiteSkipSilence injects its own settings section (ID `790`) right after
the YTVideoOverlay section. There you can:

- Master on/off.
- **Silence Threshold** — picker: −25, −30, −35, −40, −45 dBFS (default −35).
- **Silence Speed** — picker: 1.5×, 2.0×, 2.5×, 3.0×, 4.0× (default 2.5×).
- **Time Saved** — readout of cumulative seconds skipped.
- **Reset Saved Time** — clears the counter.

Advanced tunables (hold time, release time) can be tweaked via
`NSUserDefaults` suite `com.dvntm.ytlite.skipsilence` if you want to
fine-tune beyond the UI; see `Utils/SkipSilenceDefaults.h`.

## Tuning recommendations

| Setting | Default | When to change |
|---|---|---|
| Threshold | −35 dBFS | Lower (−40, −45) for very dynamic speech; higher (−25, −30) if your video has noisy background music you want to keep. |
| Silence speed | 2.5× | Lower (1.5×, 2.0×) if 2.5× feels jarring; higher (3.0×, 4.0×) if you're power-watching lectures. |
| Hold time | 150 ms | Lower (80–100 ms) for snappier skipping; higher (200–300 ms) to preserve natural pauses. |
| Release time | 40 ms | Higher (80–120 ms) if you hear "stutter" at the start of sentences. |

## File layout

```
YTLiteSkipSilence/
├── Makefile                         # Theos build
├── control                          # Debian package metadata
├── YTLiteSkipSilence.plist          # MobileSubstrate filter (com.google.ios.youtube)
├── YTLiteSkipSilence.x              # Main tweak: YTVideoOverlay button + AVPlayer hooks
├── Settings.x                       # In-app settings section (ID 790)
├── Utils/
│   ├── SkipSilenceManager.{h,m}     # MTAudioProcessingTap engine + state machine
│   ├── SkipSilenceDefaults.{h,m}    # NSUserDefaults wrapper (suite com.dvntm.ytlite.skipsilence)
│   ├── NSBundle+YTSkipSilence.{h,m} # Bundle resolution (jailbreak / rootless / sideload)
│   └── Reachability.{h,m}           # Tony Million's reachability (unused but kept for parity)
├── Resources/
│   └── YTLiteSkipSilence.bundle/
│       ├── Info.plist
│       └── en.lproj/Localizable.strings
├── .github/workflows/build.yml      # CI build
├── README.md                        # this file
├── LICENSE                          # MIT
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

The hook targets (`YTPlayerViewController`, `YTMainAppControlsOverlayView`,
`YTInlinePlayerBarContainerView`, `YTMainAppVideoPlayerOverlayViewController`)
are stable YouTube classes that YTLite, YouPiP, YouQuality, and YTVideoOverlay
all already hook — they haven't materially changed in years. The `AVPlayer` /
`AVPlayerItem` / `MTAudioProcessingTap` surface is Apple public API and is
not expected to change.

## Acknowledgements

- **[Overcast](https://overcast.fm)** by Marco Arment — original Smart Speed
  algorithm; the `OCVoiceBoostLookahead.c` look-ahead compressor/limiter
  pattern inspired this tweak's hysteresis model.
- **[YTLite](https://github.com/dayanch96/YTLite)** by dayanch96 / dvntm —
  the host tweak whose project layout and settings-injection pattern this
  tweak mirrors.
- **[YTVideoOverlay](https://github.com/PoomSmart/YTVideoOverlay)** by
  PoomSmart — the button-hosting framework this tweak registers with for
  its toggle button.
- **[YouTubeHeader](https://github.com/PoomSmart/YouTubeHeader)** and
  **[PSHeader](https://github.com/PoomSmart/PSHeader)** by PoomSmart — the
  YouTube class headers every iOS YouTube tweak depends on.
- **[Tony Million's Reachability](https://github.com/tonymillion/Reachability)**
  — public-domain reachability wrapper.

## License

MIT. See [LICENSE](LICENSE).
