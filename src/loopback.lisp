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

(defun %opposite (direction)
  (ecase direction (:to-agent :to-client) (:to-client :to-agent)))

(defun %log-line (transport direction text)
  (push (cons direction text) (car (loopback-log transport)))
  text)

(defun %peer-handler (transport)
  (or (loopback-peer-handler transport)
      (error 'acp-internal-error
             :message (format nil "Loopback ~(~A~) transport has no peer handler"
                              (loopback-direction transport)))))

(defmethod rpc-protocol:backend-rpc-call
    ((transport loopback-rpc-transport) method params &key timeout id)
  (declare (ignore timeout))
  (let* ((codec rpc-protocol-json:*jsonrpc-codec*)
         (id (or id (incf (loopback-next-id transport))))
         (handler (%peer-handler transport))
         (text (%log-line transport (loopback-direction transport)
                          (rpc-protocol:encode-request method params :id id :codec codec)))
         ;; the receiving side: decode the line, answer it
         (incoming (rpc-protocol:decode-message text :codec codec))
         (answer (%log-line transport (%opposite (loopback-direction transport))
                            (%answer handler (gethash "id" incoming)
                                     (gethash "method" incoming)
                                     (gethash "params" incoming))))
         ;; the calling side: decode the answer
         (reply (rpc-protocol:decode-message answer :codec codec)))
    (multiple-value-bind (err errorp) (gethash "error" reply)
      (if errorp
          (error 'rpc-protocol:rpc-error :code (gethash "code" err)
                                         :message (gethash "message" err)
                                         :data (gethash "data" err))
          (gethash "result" reply)))))

(defmethod rpc-protocol:backend-rpc-notify
    ((transport loopback-rpc-transport) method params)
  (let* ((codec rpc-protocol-json:*jsonrpc-codec*)
         (handler (%peer-handler transport))
         (text (%log-line transport (loopback-direction transport)
                          (rpc-protocol:encode-notification method params :codec codec)))
         (incoming (rpc-protocol:decode-message text :codec codec)))
    (%deliver-notification handler (gethash "method" incoming) (gethash "params" incoming))
    t))

(defmethod rpc-protocol:backend-rpc-serve
    ((transport loopback-rpc-transport) handler &key)
  (check-type handler function)
  (setf (loopback-peer-handler transport) handler)
  transport)

(defun make-acp-loopback (agent client)
  (check-type agent acp-agent)
  (check-type client acp-client)
  (let* ((log (list '()))
         (to-agent (make-instance 'loopback-rpc-transport :direction :to-agent :log log))
         (to-client (make-instance 'loopback-rpc-transport :direction :to-client :log log))
         (agent-side (make-acp-connection :role :agent :local agent :transport to-client))
         (client-side (make-acp-connection :role :client :local client :transport to-agent)))
    (rpc-protocol:rpc-serve (acp-connection-handler agent-side) :transport to-agent)
    (rpc-protocol:rpc-serve (acp-connection-handler client-side) :transport to-client)
    (values (acp-connection-remote client-side) (acp-connection-remote agent-side))))

(defun acp-loopback-log (remote)
  (check-type remote remote-peer)
  (let ((transport (acp-connection-transport (remote-connection remote))))
    (check-type transport loopback-rpc-transport)
    (reverse (car (loopback-log transport)))))
