# Streaming acceptance check

Compilation and synthetic tests do not establish real-device reliability.
Before using this revision for a match, test on iPhone 15 Pro with the actual Fastweb SIM:

1. 45–60 minutes of 720p streaming, including movement and crowd sound. Compare the Facebook recording, not only local preview.
2. Start/stop Camera and switch 480/720/1080 before going live several times. Confirm exactly one overlay and correct resolution; no growth in memory after repeated changes.
3. Trigger every graphic and audio cue while streaming. Check microphone clarity, cue pitch/duration and audio/video synchronization at the start and end.
4. Briefly interrupt connectivity, then restore it. Confirm bounded retries, recovery or an explicit failure message, no score reset and no accumulated old video. Facebook may end the post; recovery cannot guarantee resumption of that post.
5. Press Stop during reconnect/backoff. It must cancel recovery and never start sending again on its own.
6. Check thermal status, outbound kb/s and queue in the Camera status. Capture OSLog category Streaming if problems recur; never share stream keys or destination URLs.
7. Compare preview with the actual 16:9 recording. Logo and score use 3% broadcast margins, independent of screen dimensions; preview is aspect-fit, not cropped. Verify menu taps, focus, all three score positions and both landscape orientations.

Automated: iOS harness tests bitrate decrease/floor/slow recovery/ceiling and render size/viewport invariance; Android tests render bounds and 32→48kHz cue duration/level. Browser check tests logo/menu alignment on both apps and three screen sizes.

Known limits: no mobile or thermal soak test is possible in CI; adaptive bitrate cannot compensate for a sustained uplink below the audio+video minimum. iOS health metrics are network throughput/queue/thermal, not measured capture FPS. 480p uses 960×540 camera capture with 854×480 composition/encoding; 720p and 1080p match throughout. Android APK signing continuity is a separate unresolved issue.
