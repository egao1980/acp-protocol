# acp-protocol

CLOS [Agent Client Protocol](https://agentclientprotocol.com) (ACP) for
cl-stack: the editor ↔ agent protocol of Zed, Emacs agent-shell and others.
Protocol version **1**, pinned to the stable schema **1.34.1**.

- the message model: every stable ACP v1 request, response and notification as
  `schema-protocol` classes, including all `session/update` kinds; unknown
  fields and kinds are kept and re-emitted, never errors;
- generic functions for both roles: the agent side (`acp-initialize`,
  `acp-new-session`, `acp-prompt`, `acp-cancel`, …) that a harness implements,
  and the client side (`acp-request-permission`, `acp-session-update`,
  `acp-read-text-file`, `acp-create-terminal`, …) that an editor implements; a
  `remote-agent` / `remote-client` proxy of each role speaks JSON-RPC;
- conditions with restarts: one per ACP error code, and permission requests as
  the `acp-permission-required` condition with `allow-once` / `allow-always` /
  `reject-once` / `reject-always` / `cancel-permission` restarts;
- an in-memory loopback pair (`make-acp-loopback`) for tests and embedding.

No transport inside: JSON goes through json-protocol and schema-protocol,
JSON-RPC through `rpc-protocol` / `rpc-protocol-json`. stdio is
[`acp-backend-stdio`](https://github.com/egao1980/acp-backend-stdio).

Brief: [cl-stack/docs/capabilities/acp.md](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/acp.md).
Test fixtures are the upstream v1 examples (Apache-2.0), see
[tests/fixtures/v1/VENDOR.md](tests/fixtures/v1/VENDOR.md).
