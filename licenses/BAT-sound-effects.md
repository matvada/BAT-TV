# BAT TV — procedural sound effects

The horn.wav, crowd.wav and drums.wav shipped with this change replace all
three previous recordings/assets whose provenance was not documented.

Created for BAT TV on 2026-10-20 using scripts/generate_sound_effects.py.
Inputs are mathematical oscillators, deterministic pseudorandom noise,
envelopes and filters only. No external recordings, samples, sound libraries,
melodies, songs or downloaded material are used. The crowd effect is a
synthetic cheering/applause texture, not a recording of people.

The generation source is included for inspection and reproducibility. No
third-party audio license or attribution is required by this generation
process. This is provenance documentation, not a guarantee against automated
platform claims or clearance of music captured by the camera microphone.

Format: little-endian PCM16, mono, 32000 Hz. Durations: 1.75 / 4 / 3.75 seconds.
Peak: -6 dBFS; fade-in/out; no looping or automatic playback by graphic cards.
Native audio mixers retain their existing 25% cue / 75% microphone blend.

Regenerate: `python3 scripts/generate_sound_effects.py`
Verify both app bundles: `python3 scripts/generate_sound_effects.py --check`

The earlier files remain in Git history for traceability but are not shipped
in the new app bundles. This change does not establish the cause of the
Facebook removal of 19 October 2026.
