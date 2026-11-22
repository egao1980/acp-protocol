# acp-protocol

CLOS [Agent Client Protocol](https://agentclientprotocol.com) (ACP, protocol
version 1) for cl-stack: the message model as `schema-protocol` classes, the
agent-side and client-side generic functions, and conditions with restarts.
No transport inside — JSON-RPC goes through `rpc-protocol` /
`rpc-protocol-json`; stdio is [`acp-backend-stdio`](https://github.com/egao1980/acp-backend-stdio).

Brief: [cl-stack/docs/capabilities/acp.md](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/acp.md).

Status: skeleton. ACP-0 (0.1.0) is in progress.
