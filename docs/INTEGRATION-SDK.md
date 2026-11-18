# Integration SDK — planned, not shipped

No integration SDK/runtime or marketplace installer is implemented in this checkout. Contributors cannot yet load an external package without rebuilding Sotto. There is no working HelloSotto package yet; a manifest or static gallery alone would not satisfy that requirement.

Built-in Apple Mail and Apple Notes use reviewed native adapters and per-target Automation permissions. They are not dynamically installed SDK packages and do not make third-party executable loading available.

## Target contract

IntegrationManifest must identify publisher, stable namespaced integration ID, version, compatible Sotto range, descriptions, declared tools/input/output schemas, permissions, authentication, runtime requirements and artifact integrity. ToolRegistration must reject collisions with native IDs and reserved agent tools. Untrusted server hints cannot downgrade risk or grant permissions.

IntegrationProtocol should use a versioned data protocol between the host and a separate runtime. IntegrationRuntime, IntegrationLifecycle, IntegrationPermission and IntegrationCredentialStore must handle launch/stop/removal, per-package grants, revocation, cancellation, timeouts and scoped credential handles. Keys must stay in Keychain and must not be inherited wholesale in child environments.

IntegrationPackageValidator must check size/path limits, version compatibility, manifest/schema limits, archive traversal/symlinks, expected artifact digest and publisher authenticity before install. A SHA-256 digest establishes integrity against expected bytes; it is not publisher trust by itself. Updates changing publisher/permissions/runtime need a new review.

## Isolation and broker requirements

Do not dlopen third-party native libraries into Sotto. Separate processes prevent some crash coupling but are not security sandboxes. An executable launched with the user's ordinary permissions can bypass a host-only tool policy, so the design needs an actual constrained service or an explicit trusted-code consent boundary. Do not claim scripts are read-only solely because a manifest says so.

A trusted capability broker must validate the real operation, arguments, target, current grants, risk and verification strategy. Consequential requests must use immutable application-generated review snapshots. A runtime must not get unrestricted shell access, arbitrary Keychain reads or screen capture from an innocuous tool declaration.

## MCP requirements

Implement stdio and the supported HTTP binding deliberately, with an explicitly supported protocol version set and bounded parsing. Discover schemas conservatively; reject unsupported schema features rather than silently removing constraints. Require consent before launching any executable server, stripping unrelated credentials/environment values. Remote auth must bind the approved origin/account, handle cancellation/expiry and never forward tokens through arbitrary redirects.

The specification changes over time: consult the relevant [transport and versioning definitions](https://modelcontextprotocol.io/specification/latest/basic/transports) before implementation. Stdio process health, HTTP streaming/session behavior, schema conversion, authentication, timeouts, removal and untrusted-result handling are still pending here.

## Packaging and discovery milestones

1. Ship one actually executable HelloSotto package through the constrained runtime, with tests for install/run/revoke/remove.
2. Publish a curated registry file/artifacts under the real project GitHub repository only after package format, trusted metadata, validation and review UI work.
3. Add native discovery, permissions, install/update/remove, connection health and reporting. No payments or proprietary account requirement.
4. Bind just-in-time installation/connection to the suspended user request; install/authorize only after consent, verify, then resume once.

Until those milestones work, no marketplace item should appear as installable or ready. Monetization is a future licensing/product decision, not a shipped capability.
