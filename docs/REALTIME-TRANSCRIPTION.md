# Optional OpenAI Realtime transcription

Voice settings offers **Apple Speech** (the default) and **OpenAI Realtime**, independently of the reasoning model. The cloud adapter follows the [official transcription guide](https://developers.openai.com/api/docs/guides/realtime-transcription.md). It does not provide ChatGPT subscription sign-in or free API access.

Select OpenAI Realtime, explicitly enable **Allow audio to OpenAI**, and save your API key to macOS Keychain. This audio permission is separate from remote reasoning consent. Apple Speech remains available without an OpenAI account. There is no automatic speech-provider fallback.

The native AVAudioEngine capture sends mono 24 kHz little-endian PCM16 through an ephemeral, authenticated URLSession WebSocket to the public OpenAI transcription endpoint. The configured model is `gpt-live-transcribe`, low-delay transcription, with automatic turn detection disabled. Release, toggle-stop or Send closes capture and commits one explicit audio turn. Live deltas update the capsule; only the completed transcript for the acknowledged committed item reaches the agent.

Escape stops capture, closes the connection and discards the command. Audio already transmitted cannot be recalled. Sotto never saves recordings. API billing and OpenAI's data policies apply. Removing consent or changing the speech destination cancels the active recording. A transcription-only test may send audio when this backend is selected and consented, but never invokes agent tools unless Run command is clicked afterward.

The transport refuses redirects, uses no shared cookies/cache, bounds buffers/text/events and has connection/finalization deadlines. An incomplete stream, missing final transcript or authentication/network failure reports failure; partial text is not used as an executable fallback. Raw server errors are not shown because they may contain private transcript text.

Protocol tests use an injected transport and cover events, item identity, cancellation, deadlines, commit ordering, malformed/incomplete responses and privacy defaults. An explicit synthetic-speech API round trip also passed with the user's existing Keychain credential; no microphone, personal speech or desktop action was involved. It is opt-in and uses billable API access:

```sh
SOTTO_REALTIME_TEST=1 swift test --filter LiveRealtimeTranscriptionTests
```

See [real-time voice](REALTIME-VOICE.md) for the Apple backend, safe preparation, timing boundaries and manual acceptance checklist.
