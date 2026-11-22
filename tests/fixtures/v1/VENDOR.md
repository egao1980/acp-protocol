# Vendored ACP v1 examples

Source: [`agentclientprotocol/agent-client-protocol`](https://github.com/agentclientprotocol/agent-client-protocol)
at tag **`schema-v1.34.1`** (2026-11-21), protocol version **1**.

License: **Apache License 2.0** — the upstream repository's license, copied
verbatim as [`LICENSE-APACHE-2.0`](LICENSE-APACHE-2.0). The files here are
unmodified JSON values taken from that repository (re-indented only); the rest
of acp-protocol is MIT.

| Files | Taken from |
|-------|------------|
| `meta.json` | `schema/v1/meta.json` (the stable method names) |
| `<page>-NN.json` | the `json` code blocks of `docs/protocol/v1/<page>.mdx` that are whole JSON-RPC 2.0 messages, in page order |
| `fragment-<page>-NN.json` | `json` code blocks of the same pages that are one typed value (a content block, a tool call content item, an MCP server, an auth method, a config option) |

Every message file validates against `schema/v1/schema.json` of the same tag.
Partial capability snippets (blocks that are not a whole message or a whole
typed value) are not vendored.

A response carries no method. `tests/model-test.lisp` names the method of each
response: the request with the same id earlier on the same page, or, where the
page shows the response alone, the method its result belongs to (`initialize`
for the capability examples, `session/new` for `session-modes-01` and
`session-config-options-01`, `session/prompt` for `error-01`).

To refresh for a new schema release, re-extract from the new tag and update
`+acp-schema-version+` and the rows in `tests/model-test.lisp` together.
