(in-package #:acp-protocol)

;;; In-memory loopback pair (contract ACP-0). GIVEN: the transport class.
;;; STUBBED: its RPC-PROTOCOL backend methods, MAKE-ACP-LOOPBACK and
;;; ACP-LOOPBACK-LOG.
;;;
;;; An agent and a client in one image, for tests and for embedding. Each
;;; direction is a LOOPBACK-RPC-TRANSPORT, an RPC-PROTOCOL:RPC-TRANSPORT
;;; whose PEER-HANDLER is the other side's ACP-CONNECTION-HANDLER. Everything
;;; crosses as JSON-RPC text through rpc-protocol-json:
;;;
;;;   BACKEND-RPC-CALL: the next id of this transport (1, 2, …), the request
;;;     text from RPC-PROTOCOL:ENCODE-REQUEST with *JSONRPC-CODEC*, logged;
;;;     the receiving side decodes that text and calls the peer handler with
;;;     *ACP-INCOMING-KIND* :request; the answer is encoded with
;;;     ENCODE-RESPONSE / ENCODE-ERROR-RESPONSE (the handler's RPC-ERROR, or
;;;     -32603 for any other error), logged, decoded again by the caller and
;;;     returned as the decoded result, or signalled as RPC-PROTOCOL:RPC-ERROR
;;;     with the code, message and data of the error object.
;;;   BACKEND-RPC-NOTIFY: ENCODE-NOTIFICATION, logged, decoded, peer handler
;;;     with *ACP-INCOMING-KIND* :notification; errors dropped; → T.
;;;   BACKEND-RPC-SERVE TRANSPORT HANDLER: sets PEER-HANDLER; → TRANSPORT.
;;;
;;; Calls are synchronous and nest: a handler may call back through the other
;;; transport (an agent's ACP-PROMPT asking permission, streaming updates,
;;; reading files) on the same thread, so a turn is deterministic with no
;;; threads. A notification is delivered before the call that sent it
;;; returns, so updates arrive in order and before the prompt response.
;;;
;;; MAKE-ACP-LOOPBACK AGENT CLIENT → (values REMOTE-AGENT REMOTE-CLIENT).
;;;   Two connections (role :agent with AGENT, role :client with CLIENT), two
;;;   transports, one shared log. REMOTE-AGENT is the client connection's
;;;   proxy (what client code calls); REMOTE-CLIENT the agent connection's
;;;   (what the agent calls back, also bound to *ACP-REMOTE* while an agent GF
;;;   runs).
;;; ACP-LOOPBACK-LOG REMOTE → the shared log, oldest first: a list of
;;;   (DIRECTION . TEXT), DIRECTION :to-agent or :to-client, TEXT the exact
;;;   JSON-RPC line (requests, responses, errors and notifications). REMOTE is
;;;   either proxy of the pair.

(defclass loopback-rpc-transport (rpc-protocol:rpc-transport)
  ((direction :initarg :direction :reader loopback-direction
              :documentation ":to-agent or :to-client: where this transport delivers.")
   (peer-handler :initform nil :accessor loopback-peer-handler)
   (next-id :initform 0 :accessor loopback-next-id)
   (log :initarg :log :reader loopback-log
        :documentation "A cons whose CAR is the shared log, newest first."))
  (:documentation "One direction of an in-memory ACP connection."))

(defmethod rpc-protocol:backend-rpc-call
    ((transport loopback-rpc-transport) method params &key timeout id)
  (declare (ignore method params timeout id))
  (%acp0-pending 'loopback-rpc-call))

(defmethod rpc-protocol:backend-rpc-notify
    ((transport loopback-rpc-transport) method params)
  (declare (ignore method params))
  (%acp0-pending 'loopback-rpc-notify))

(defmethod rpc-protocol:backend-rpc-serve
    ((transport loopback-rpc-transport) handler &key)
  (declare (ignore handler))
  (%acp0-pending 'loopback-rpc-serve))

(defun make-acp-loopback (agent client)
  (declare (ignore agent client))
  (%acp0-pending 'make-acp-loopback))

(defun acp-loopback-log (remote)
  (declare (ignore remote))
  (%acp0-pending 'acp-loopback-log))
