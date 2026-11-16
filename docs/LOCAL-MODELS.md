# Local reasoning with Ollama

Sotto supports the native Ollama chat API alongside OpenAI. Speech recognition stays independent of reasoning. No Sotto account or OpenAI key is needed when Ollama is selected.

## Set up

Choose **Intelligence → Enable intelligence… → Enable local intelligence**. Sotto finds an installed Ollama executable, starts a loopback-only engine when needed, waits for readiness and verifies installed models. It selects a compatible installed model and resumes the waiting request. There is no terminal step or model picker in this path.

If the engine is missing, the sheet links to the [official Ollama macOS app download](https://ollama.com/download/mac). Automatic runtime installation and model downloads are not implemented yet. If there is no compatible installed model, Sotto explains that limitation rather than claiming it is ready or downloading weights without consent.

Sotto starts `ollama serve` as a child process directly; it does not open Terminal, invoke a shell, register a launch agent or change Homebrew services. Its child is bound to IPv4 loopback with cloud features disabled. Only fixed known app/Homebrew installation locations are searched; shell PATH and workspace executables are not used. Provider keys and proxy settings are not inherited.

Existing servers are reused and never terminated by Sotto. The managed child stays alive during requests and stops after five idle minutes or when Sotto quits; it restarts automatically when needed. Advanced custom endpoints are reused when healthy but not spawned automatically. Local speech remains a separate Voice setting.

## Supported boundary

- The destination must be a root HTTP/HTTPS loopback address: `127.0.0.1`, `localhost` (normalized to the literal IPv4 address), or `::1`, with an optional port. Remote/LAN addresses, URL credentials, paths, queries and fragments are rejected. Redirects are refused and the local session overrides proxy routing. HTTPS still uses normal certificate validation.
- Discovery uses `/api/tags` and `/api/show`. A model must advertise `tools` capability. Unknown capabilities are not guessed. Advertised cloud-backed tags/aliases are disabled, and metadata is checked again before sending each inference request. Run the server with `OLLAMA_NO_CLOUD=1` for server-side local-only operation as well; the external server controls its own configuration.
- Local requests never carry the OpenAI Authorization header or read its secret. OpenAI consent is not required for Ollama. Switching provider/model/address cancels the active operation and clears the in-memory conversation so context is not transferred between destinations. Existing credentials, history and per-provider choices are preserved. Failure does not trigger an automatic provider switch.
- If the standard server is stopped, Sotto starts it when local intelligence is needed. An absent model, unsupported tool capability, malformed/truncated stream or HTTP failure produces an error. No tool calls execute until a complete, valid model response has been received. The trusted registry validates inputs and the authorization gate evaluates consequential actions independently of the model.
- There is no remote Ollama authentication, cloud inference, compatible-endpoint API mode or automatic model downloader in this milestone. The model's advertised capability is not a guarantee of its judgment; smaller models can choose incorrect arguments. Native errors remain errors rather than successful confirmations.

## Adapter and contributor notes

The adapter translates Sotto's message/function-call/function-result history into Ollama's assistant/tool messages and maps completed tool calls back to unique canonical call IDs. Tool results remain role `tool`, including content that looks like instructions. Model thinking metadata is retained for the next local reasoning round without being displayed as user-facing text. The model's default thinking behavior is respected.

The implementation follows the official [chat API](https://docs.ollama.com/api/chat), [tool calling](https://docs.ollama.com/capabilities/tool-calling) and [API types](https://github.com/ollama/ollama/blob/main/api/types.go). Streaming uses bounded newline-delimited JSON with strict completion checks. Current limits: 64 catalog entries, 2 MiB metadata responses, 8 MiB total streamed response, 256 KiB per line/thinking text, 128 KiB answer text and 16 calls per response. Generation requests use an 8192-token context, a 2048-token output limit and one-minute model keep-alive. The agent still has its independent eight-round limit. These bounds are implementation defaults, not performance claims.

```sh
swift test
# Opt-in: requires the local server/model; opens the actual Downloads folder.
SOTTO_OLLAMA_TESTS=1 swift test --filter LiveOllamaTests
```

Protocol fixtures test endpoint validation, cloud gating before transcript transmission, redirects, credentials absent from HTTP headers, streaming, tool-result translation, malformed/incomplete responses, cancellation and stale discovery. The live test uses the actual model, agent loop and Finder adapter, then checks that the model consumes the confirmed result. Neither test path needs an OpenAI key.

## Runtime lifecycle validation

Process and readiness injection tests cover ownership, reuse, bounded startup, cancellation, custom endpoints and idle leases. Opt-in `SOTTO_RUNTIME_TEST=1 swift test --filter ManagedOllamaRuntimeTests` checks the installed engine without downloads or inference. A separate isolated loopback port verifies actual child startup, catalog access and termination while preserving an existing server.
