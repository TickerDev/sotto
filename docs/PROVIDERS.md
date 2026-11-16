# Provider and harness research

Reviewed November 15, 2026. OpenAI direct API and local Ollama are implemented. The OpenAI key is user-supplied and stored in Keychain; Ollama does not use it. Native app use of a user-owned key is intentional: there is no embedded shared secret or proprietary backend. See [local model setup and adapter limits](LOCAL-MODELS.md).

The implementation follows official [function calling](https://developers.openai.com/api/docs/guides/function-calling) and [streaming](https://developers.openai.com/api/docs/guides/streaming-responses) documentation: local schema definitions, streamed completion, completed function arguments, actual function outputs, then another reasoning round. Requests use store:false. Responses are never followed to a different host by redirect, and authentication failures are shown without logging the API key or response body.

## Codex app-server: researched, unavailable in Sotto

The official [Codex App Server documentation](https://learn.chatgpt.com/docs/app-server) describes a supported integration for authentication, threads, approvals and streamed events. The lifecycle includes an initialize/initialized handshake, thread/start, turn/start, item notifications, turn/completed and turn/interrupt. This is a stateful harness protocol, not a drop-in general API key transport.

Official [Sign in with ChatGPT app-server guidance](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server) documents the current route for user-authorized plan-backed use. Eligibility, scopes, model availability and current terms must be verified when implementing. A ChatGPT subscription is not itself general API authorization. Sotto does not reuse Codex credential files.

[T3 Code's Codex driver](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/Drivers/CodexDriver.ts) separates provider lifecycle/status probing and a Codex adapter from its internal event model. Sotto should adopt the separation, using an officially installed harness and explicit authentication rather than credential extraction.

Before enabling this route, implement a cancellable transport, version/capability negotiation, explicit user auth, thread lifecycle, and structured event mapping. Restrict the harness's built-in shell/file capabilities so they cannot bypass Sotto's tool risk policy; expose only reviewed native tools through a controlled bridge. Verify app-server approval and cancellation behavior with integration tests. Until those constraints are met, Settings labels it research only.

## Capability discovery

The OpenAI models endpoint supplies account-visible identifiers but no complete tool-capability contract. Sotto therefore exposes a conservative vetted model list. An unknown OpenAI model fails before inference. Ollama uses its native model capabilities endpoint, rejects cloud-backed metadata and rechecks tool support before each inference request. Its loopback endpoint, stream translation and cancellation have separate protocol and real-server tests. Other compatible endpoints remain unavailable and require separate authentication, schema, cancellation and capability handling before they are enabled.
