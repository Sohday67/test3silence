# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-06-30

### Added
- Initial release of YTLiteSkipSilence.
- Overcast-style real-time silence detector via `MTAudioProcessingTap` attached
  to YouTube's `AVPlayerItem.audioMix`.
- Hysteresis state machine: hold time (150 ms) before silence-speed engages,
  release time (40 ms) before normal rate is restored. Prevents chatter on
  noisy speech.
- YTVideoOverlay toggle button (default position: bottom player bar, next to
  fullscreen). Tap to toggle; icon swaps between `speaker.slash.fill` (off)
  and `speaker.wave.3.fill` (on) via SF Symbols.
- In-app settings section (ID 790) injected into YouTube's settings UI:
  - Master on/off switch
  - Silence threshold picker: −25, −30, −35, −40, −45 dBFS (default −35)
  - Silence speed picker: 1.5×, 2.0×, 2.5×, 3.0×, 4.0× (default 2.5×)
  - "Time saved" readout (cumulative seconds skipped)
  - "Reset saved time" button
- User-rate capture: hooks `-[AVPlayer setRate:]`,
  `-[YTPlayerViewController setPlaybackRate:]`, and
  `-[YTMainAppVideoPlayerOverlayViewController setPlaybackRate:]` to learn
  the user's chosen "normal" rate, so silence-speed restores to it.
- Lightweight HUD toast when silence is being skipped (configurable on/off).
- Bundle resolution supporting classic jailbreak, rootless, roothide, and
  sideloaded-embedded installs.
- GitHub Actions CI building rootless + roothide + classic `.deb` artifacts.

### Algorithm

- Per-render-cycle RMS computation across all channels.
- RMS → dBFS via `20 * log10(rms)` (clamped to −160 dBFS).
- Comparison against user-set threshold.
- Hysteresis via `(belowSince, aboveSince)` timestamps.
- Silence-speed applied by setting `AVPlayer.rate`.
- Time-saved counter incremented by `(silenceRate − userRate) / silenceRate * bufferDuration`.

### Dependencies

- `com.ps.ytvideooverlay` (>= 2.0.0)
- iOS 13.0+
- YouTube 19.x or 20.x

### Acknowledgements

- Overcast by Marco Arment — the original Smart Speed algorithm that inspired
  this tweak. The Overcast IPA was used as a behavioural reference; this is an
  independent reimplementation under the MIT license.
- YTLite by dayanch96 / dvntm — the host tweak whose patterns we mirror.
- YTVideoOverlay by PoomSmart — the button-hosting framework.
