(in-package #:acp-protocol)

;;; Peers, generic functions and connections (contract ACP-0).
;;;
;;; GIVEN: the classes, the GFs, their default methods that need no
;;; behaviour (ACP-METHOD-NOT-FOUND / ignore), the REMOTE-AGENT and
;;; REMOTE-CLIENT methods (each one line onto REMOTE-CALL / REMOTE-NOTIFY),
;;; MAKE-ACP-CONNECTION. STUBBED: REMOTE-CALL, REMOTE-NOTIFY,
;;; ACP-CONNECTION-HANDLER, ACP-HANDLE-MESSAGE, the default
;;; ACP-REQUEST-PERMISSION method, ACP-SEND-UPDATE, ACP-ASK-PERMISSION,
;;; ACP-CALL-EXT, ACP-NOTIFY-EXT.
;;;
;;; Shape. The same GFs serve both ends. A harness subclasses ACP-AGENT and
;;; defines methods on the agent-side GFs; an editor subclasses ACP-CLIENT and
;;; defines methods on the client-side GFs. Each side talks to the other
;;; through a proxy of the other role — REMOTE-AGENT (a client's view of the
;;; agent) or REMOTE-CLIENT (an agent's view of the client) — whose methods
;;; on the same GFs send JSON-RPC. So an agent streams an update with
;;; (ACP-SESSION-UPDATE remote-client notification) and asks permission with
;;; (ACP-REQUEST-PERMISSION remote-client request).
;;;
;;; Every GF takes (PEER PARAMS-OBJECT) and returns the response object (an
;;; instance of the method's response class, +ACP-METHODS+), or anything for
;;; a notification.
;;;
;;; ACP-CONNECTION. One per side of one connection: ROLE is the LOCAL role
;;; (:agent or :client), LOCAL the local peer, TRANSPORT an
;;; RPC-PROTOCOL:RPC-TRANSPORT that sends to the other side, REMOTE the
;;; proxy of the other role (made by MAKE-ACP-CONNECTION). The connection
;;; records what initialize exchanged: PROTOCOL-VERSION, CLIENT-CAPABILITIES,
;;; CLIENT-INFO, AGENT-CAPABILITIES, AGENT-INFO, INITIALIZED-P — on the agent
;;; side when the request is handled, on the client side when the response
;;; arrives (REMOTE-AGENT's ACP-INITIALIZE).
;;;
;;; ACP-CONNECTION-HANDLER CONNECTION → (lambda (method params)), the
;;;   RPC-PROTOCOL handler of the incoming side (what RPC-SERVE / a backend's
;;;   :on-request / :on-notification calls; PARAMS is decoded JSON). It
;;;   returns the result as a JSON value (ACP-OBJECT-TABLE of the response
;;;   object) or signals RPC-PROTOCOL:RPC-ERROR with the ACP-ERROR-FOR code,
;;;   message and data. While a GF runs, *ACP-CONNECTION* is CONNECTION and
;;;   *ACP-REMOTE* its REMOTE. Rules, in order:
;;;   1. METHOD in +ACP-METHODS+ whose direction is the local role (or
;;;      :both): params → PARSE-ACP-OBJECT of the request class (failure →
;;;      -32602), then (GF LOCAL params-object).
;;;      * Agent role, before initialize has been handled: a request other
;;;        than "initialize" → -32600; a notification is dropped.
;;;      * Agent role, "initialize": record CLIENT-CAPABILITIES / CLIENT-INFO
;;;        (NIL when absent), call the GF, then an unbound PROTOCOL-VERSION in
;;;        the response becomes +ACP-PROTOCOL-VERSION+ (the version
;;;        negotiation: this build speaks only 1, and answers 1 to any
;;;        request); record PROTOCOL-VERSION, AGENT-CAPABILITIES, AGENT-INFO
;;;        and set INITIALIZED-P.
;;;      * "session/prompt": an ACP-REQUEST-CANCELLED out of the GF is
;;;        answered with the result {"stopReason":"cancelled"}, not an error
;;;        (spec: cancellation is not an error for a prompt turn).
;;;      * Client role, "session/request_permission": when the local client
;;;        sent session/cancel for that session (REMOTE-AGENT's ACP-CANCEL)
;;;        after the request arrived and before the GF returned, the answer
;;;        is the `cancelled` outcome whatever the GF returned (spec: the
;;;        client MUST answer pending permission requests of a cancelled
;;;        turn with cancelled).
;;;   2. METHOD in +ACP-METHODS+ for the other role: a request → -32601; a
;;;      notification is dropped.
;;;   3. An extension method (ACP-EXTENSION-METHOD-P): a request →
;;;      (ACP-EXT-METHOD LOCAL method params) with the raw PARAMS, its value
;;;      the raw result; a notification → (ACP-EXT-NOTIFICATION LOCAL method
;;;      params).
;;;   4. Anything else: a request → -32601; a notification is dropped
;;;      (unknown notifications are ignored, never an error).
;;;   A request's handler error: ACP-ERROR → its code / message / data; any
;;;   other ERROR → -32603 with its text. A notification's errors are
;;;   dropped. Non-error conditions (ACP-PERMISSION-REQUIRED) pass through.
;;;   The dispatcher cannot tell a request from a notification by its
;;;   arguments, so it treats METHOD as the table says; for unknown methods
;;;   a backend tells it with *ACP-INCOMING-KIND* (:request / :notification,
;;;   default :request), bound around the call.
;;;
;;; ACP-HANDLE-MESSAGE CONNECTION SOURCE → the answer as JSON-RPC text, or
;;;   NIL for a notification. SOURCE is one JSON-RPC message text. Decodes it
;;;   (not JSON / not a JSON-RPC object → the -32700 / -32600 error answer
;;;   with "id": null), binds *ACP-INCOMING-KIND*, calls the handler, encodes
;;;   the result or the error with the request's id. For tests and for
;;;   transports that hand over raw lines.
;;;
;;; REMOTE-CALL REMOTE METHOD REQUEST &key TIMEOUT → the response object.
;;;   REMOTE is a REMOTE-AGENT or REMOTE-CLIENT; METHOD a request of the
;;;   other role in +ACP-METHODS+; REQUEST its request object (or a
;;;   hash-table). When the connection is initialized and the row has a
;;;   CAPABILITY the peer did not advertise (AGENT-SUPPORTS-P for a
;;;   REMOTE-AGENT, CLIENT-SUPPORTS-P for a REMOTE-CLIENT): signal
;;;   ACP-UNSUPPORTED (METHOD, FEATURE) without sending. Otherwise
;;;   RPC-PROTOCOL:RPC-CALL on the connection's transport with
;;;   (ACP-OBJECT-TABLE REQUEST); the result → PARSE-ACP-OBJECT of the
;;;   response class (a result that does not parse → ACP-INTERNAL-ERROR); an
;;;   RPC-ERROR → the ACP-CONDITION-FOR its code, signalled with ERROR inside
;;;   RESTART-CASE RETRY (call again) / USE-VALUE (return the value).
;;; REMOTE-NOTIFY REMOTE METHOD NOTIFICATION → T. Same capability check
;;;   (none of the stable notifications is gated, see ACP-SESSION-UPDATE
;;;   below), then RPC-PROTOCOL:RPC-NOTIFY.
;;;
;;; ACP-SEND-UPDATE REMOTE-CLIENT SESSION-ID UPDATE → T: an ACP-SESSION-UPDATE
;;;   with a SESSION-NOTIFICATION. UPDATE-PLAN-UPDATE and UPDATE-PLAN-REMOVED
;;;   need the client's :plan-operations (else ACP-UNSUPPORTED, nothing sent;
;;;   the agent sends the full UPDATE-PLAN instead) — the check is in
;;;   REMOTE-CLIENT's ACP-SESSION-UPDATE, so it applies to both.
;;; ACP-ASK-PERMISSION REMOTE-CLIENT SESSION-ID TOOL-CALL OPTIONS → (values
;;;   KIND OPTION-ID). TOOL-CALL a TOOL-CALL-UPDATE; OPTIONS a list of
;;;   PERMISSION-OPTIONs, or of (option-id name kind) lists. KIND is the
;;;   chosen option's kind as a keyword (:allow-once :allow-always
;;;   :reject-once :reject-always; an unknown kind string is upcased and
;;;   interned in KEYWORD), or :cancelled (OPTION-ID NIL). An option id the
;;;   client chose that is not among OPTIONS → ACP-INTERNAL-ERROR.
;;; Default ACP-REQUEST-PERMISSION on ACP-CLIENT: SIGNAL
;;;   ACP-PERMISSION-REQUIRED (:REQUEST, :CONNECTION *ACP-CONNECTION*) with
;;;   the restarts documented on the condition; the outcome is
;;;   SELECTED-PERMISSION-OUTCOME of the chosen option, or
;;;   CANCELLED-PERMISSION-OUTCOME (CANCEL-PERMISSION, or no handler). An
;;;   unknown option id given to SELECT-PERMISSION-OPTION →
;;;   ACP-INVALID-PARAMS.
;;; ACP-CALL-EXT REMOTE METHOD PARAMS → the raw result; ACP-NOTIFY-EXT REMOTE
;;;   METHOD PARAMS → T. METHOD must be an extension name, else
;;;   ACP-INVALID-REQUEST without sending. Errors as REMOTE-CALL.
;;;
;;; Multi-client (later): an agent with several attached clients offers a
;;; permission request to every one and the first answer wins; ACP-0 has one
;;; connection per session and ACP-ASK-PERMISSION takes one REMOTE-CLIENT.

(defvar *acp-connection* nil "The connection whose incoming message is being handled.")
(defvar *acp-remote* nil "Its REMOTE proxy (the other side) while a GF runs.")
(defvar *acp-incoming-kind* :request
  "Set by a transport around ACP-CONNECTION-HANDLER for methods the table
does not know: :request or :notification.")

(defclass acp-peer ()
  ((info :initarg :info :initform nil :accessor acp-peer-info
         :documentation "An IMPLEMENTATION (name / title / version), or NIL."))
  (:documentation "One end of an ACP connection."))

(defclass acp-agent (acp-peer) ()
  (:documentation "Agent side. Harnesses subclass it and implement the agent GFs."))

(defclass acp-client (acp-peer) ()
  (:documentation "Client (editor) side. Implement the client GFs on a subclass."))

(defclass remote-peer ()
  ((connection :initarg :connection :reader remote-connection))
  (:documentation "A proxy whose GF methods send JSON-RPC over CONNECTION."))

(defclass remote-agent (acp-agent remote-peer) ()
  (:documentation "A client's view of the agent."))

(defclass remote-client (acp-client remote-peer) ()
  (:documentation "An agent's view of the client."))

(defclass acp-connection ()
  ((role :initarg :role :reader acp-connection-role)
   (local :initarg :local :reader acp-connection-local)
   (transport :initarg :transport :initform nil :accessor acp-connection-transport)
   (remote :initform nil :accessor acp-connection-remote)
   (initialized-p :initform nil :accessor acp-connection-initialized-p)
   (protocol-version :initform nil :accessor acp-connection-protocol-version)
   (client-capabilities :initform nil :accessor acp-connection-client-capabilities)
   (client-info :initform nil :accessor acp-connection-client-info)
   (agent-capabilities :initform nil :accessor acp-connection-agent-capabilities)
   (agent-info :initform nil :accessor acp-connection-agent-info)
   (cancel-counts :initform (make-hash-table :test 'equal) :reader acp-connection-cancel-counts
                  :documentation "Client role: session id → session/cancel sent so far.")
   (lock :initform (bt2:make-lock :name "acp connection") :reader acp-connection-lock))
  (:documentation "One side of one ACP connection."))

(defun make-acp-connection (&key role local transport)
  "A connection whose local side is LOCAL in ROLE (:agent / :client),
sending through TRANSPORT. Its REMOTE is a proxy of the other role."
  (check-type role (member :agent :client))
  (let ((c (make-instance 'acp-connection :role role :local local :transport transport)))
    (setf (acp-connection-remote c)
          (make-instance (if (eq role :agent) 'remote-client 'remote-agent) :connection c))
    c))

;;; --- incoming side ---------------------------------------------------------------

(defun %slot-or-nil (object slot)
  "SLOT of OBJECT, or NIL when unbound or JSON null."
  (when (and (%schema-object-p object) (slot-boundp object slot))
    (let ((v (slot-value object slot)))
      (unless (eq v :null) v))))

(defun %cancel-count (connection session-id)
  (bt2:with-lock-held ((acp-connection-lock connection))
    (gethash session-id (acp-connection-cancel-counts connection) 0)))

(defun %invoke-local (connection method gf local object)
  "(GF LOCAL OBJECT) with the per-method rules 1.* of the dispatcher."
  (let ((role (acp-connection-role connection)))
    (cond
      ((and (eq role :agent) (string= method "initialize"))
       (setf (acp-connection-client-capabilities connection)
             (%slot-or-nil object 'client-capabilities)
             (acp-connection-client-info connection) (%slot-or-nil object 'client-info))
       (let ((response (funcall gf local object)))
         (when (and (%schema-object-p response)
                    (not (slot-boundp response 'protocol-version)))
           (setf (protocol-version response) +acp-protocol-version+))
         (setf (acp-connection-protocol-version connection)
               (%slot-or-nil response 'protocol-version)
               (acp-connection-agent-capabilities connection)
               (%slot-or-nil response 'agent-capabilities)
               (acp-connection-agent-info connection) (%slot-or-nil response 'agent-info)
               (acp-connection-initialized-p connection) t)
         response))
      ((string= method "session/prompt")
       (handler-case (funcall gf local object)
         (acp-request-cancelled ()
           (make-acp 'prompt-response :stop-reason "cancelled"))))
      ((and (eq role :client) (string= method "session/request_permission"))
       (let* ((session-id (session-id object))
              (before (%cancel-count connection session-id))
              (response (funcall gf local object)))
         (if (> (%cancel-count connection session-id) before)
             (make-acp 'request-permission-response
                       :outcome (make-acp 'cancelled-permission-outcome))
             response)))
      (t (funcall gf local object)))))

(defun %dispatch (connection method row kind params)
  "Rules 1–4 of ACP-CONNECTION-HANDLER → the JSON result (requests) or NIL."
  (let ((role (acp-connection-role connection))
        (local (acp-connection-local connection)))
    (cond
      ((and (eq role :agent)
            (not (acp-connection-initialized-p connection))
            (not (equal method "initialize")))
       (when (eq kind :request)
         (error 'acp-invalid-request
                :message (format nil "Request before initialize: ~A" method))))
      ((and row (member (second row) (list role :both)))
       (let* ((object (parse-acp-object (fourth row) (%params-object params)))
              (value (%invoke-local connection method (sixth row) local object)))
         (when (eq kind :request)
           (if value (acp-object-table value) (make-hash-table :test 'equal)))))
      ((acp-extension-method-p method)
       (if (eq kind :request)
           (acp-ext-method local method params)
           (acp-ext-notification local method params)))
      ((eq kind :request) (%not-found method)))))

(defun acp-connection-handler (connection)
  (check-type connection acp-connection)
  (lambda (method params)
    (let* ((*acp-connection* connection)
           (*acp-remote* (acp-connection-remote connection))
           (row (and (stringp method) (acp-method-row method)))
           (kind (if row (third row) *acp-incoming-kind*)))
      (if (eq kind :notification)
          (handler-case (progn (%dispatch connection method row :notification params) nil)
            (error () nil))
          ;; Innermost handler: outer HANDLER-BINDs (the caller's, live through the
          ;; synchronous loopback) never see this side's own errors. ERROR only, so
          ;; ACP-PERMISSION-REQUIRED passes through.
          (handler-case (%dispatch connection method row :request params)
            (error (e)
              (multiple-value-bind (code message data) (acp-error-for e)
                (error 'rpc-protocol:rpc-error :code code :message message :data data))))))))

(defun %answer (handler id method params)
  "Call HANDLER for the request METHOD / PARAMS → the JSON-RPC answer text
with ID: the result, the handler's RPC-ERROR, or -32603 for any other error."
  (let ((codec rpc-protocol-json:*jsonrpc-codec*)
        (*acp-incoming-kind* :request))
    (handler-case
        (rpc-protocol:encode-response (funcall handler method params) :id id :codec codec)
      (rpc-protocol:rpc-error (e)
        (rpc-protocol:encode-error-response
         (rpc-protocol:rpc-error-code e)
         (or (rpc-protocol:rpc-error-message e) (princ-to-string e))
         :id id :data (rpc-protocol:rpc-error-data e) :codec codec))
      (error (e)
        (rpc-protocol:encode-error-response rpc-protocol:+internal-error+ (princ-to-string e)
                                            :id id :codec codec)))))

(defun %deliver-notification (handler method params)
  "Call HANDLER for the notification METHOD / PARAMS; errors are dropped."
  (let ((*acp-incoming-kind* :notification))
    (handler-case (funcall handler method params)
      (error () nil))
    nil))

(defun acp-handle-message (connection source)
  (check-type connection acp-connection)
  (let ((codec rpc-protocol-json:*jsonrpc-codec*))
    (multiple-value-bind (table kind problem) (%envelope source)
      (case problem
        (:parse
         (rpc-protocol:encode-error-response rpc-protocol:+parse-error+ "Parse error"
                                             :id :null :codec codec))
        (:invalid
         (rpc-protocol:encode-error-response rpc-protocol:+invalid-request+ "Invalid request"
                                             :id :null :codec codec))
        (t
         (let ((handler (acp-connection-handler connection))
               (method (gethash "method" table))
               (params (gethash "params" table)))
           (case kind
             (:request (%answer handler (gethash "id" table) method params))
             (:notification (%deliver-notification handler method params))
             ;; responses / errors are answers to our own calls: not ours to handle here
             (t nil))))))))

;;; --- calling side ----------------------------------------------------------------

(defun %check-capability (remote method)
  "Signal ACP-UNSUPPORTED when METHOD is gated on a capability the initialized
peer did not advertise."
  (let* ((connection (remote-connection remote))
         (feature (acp-method-capability method)))
    (when (and feature (acp-connection-initialized-p connection))
      (unless (etypecase remote
                (remote-agent (agent-supports-p
                               (acp-connection-agent-capabilities connection) feature))
                (remote-client (client-supports-p
                                (acp-connection-client-capabilities connection) feature)))
        (error 'acp-unsupported
               :method method :feature feature
               :message (format nil "Capability ~(~A~) not advertised by the peer" feature))))))

(defun %remote-request (remote method params &key timeout (parse #'identity))
  "RPC-CALL METHOD on REMOTE's transport; the result through PARSE. An error
answer is signalled as its ACP condition with RETRY / USE-VALUE."
  (let ((transport (acp-connection-transport (remote-connection remote))))
    (loop
      (let ((condition
              (handler-case
                  (let ((result (rpc-protocol:rpc-call method params :timeout timeout
                                                                     :transport transport)))
                    (handler-case (return-from %remote-request (funcall parse result))
                      (acp-error (e)
                        (make-condition 'acp-internal-error
                                        :cause e :data (acp-error-data e)
                                        :message (format nil "Malformed ~A result: ~A"
                                                         method e)))))
                (rpc-protocol:rpc-error (e)
                  (acp-condition-for (rpc-protocol:rpc-error-code e)
                                     (or (rpc-protocol:rpc-error-message e) "")
                                     (rpc-protocol:rpc-error-data e))))))
        (restart-case (error condition)
          (retry ()
            :report (lambda (s) (format s "Send the ~A request again." method))
            nil)
          (use-value (value)
            :report "Return a value instead of the response."
            :interactive (lambda ()
                           (format *query-io* "Value: ")
                           (force-output *query-io*)
                           (list (eval (read *query-io*))))
            (return-from %remote-request value)))))))

(defun remote-call (remote method request &key timeout)
  (check-type remote remote-peer)
  (check-type method string)
  (%check-capability remote method)
  (let ((class (acp-method-response-class method)))
    (%remote-request remote method (acp-object-table request)
                     :timeout timeout
                     :parse (if class
                                (lambda (result) (parse-acp-object class result))
                                #'identity))))

(defun remote-notify (remote method notification)
  (check-type remote remote-peer)
  (check-type method string)
  (%check-capability remote method)
  (rpc-protocol:rpc-notify method (acp-object-table notification)
                           :transport (acp-connection-transport (remote-connection remote)))
  t)

;;; --- agent-side GFs (client → agent) ----------------------------------------

(defgeneric acp-initialize (agent request)
  (:documentation "initialize → INITIALIZE-RESPONSE."))
(defgeneric acp-authenticate (agent request)
  (:documentation "authenticate → AUTHENTICATE-RESPONSE."))
(defgeneric acp-logout (agent request)
  (:documentation "logout → LOGOUT-RESPONSE (agent capability auth.logout)."))
(defgeneric acp-new-session (agent request)
  (:documentation "session/new → NEW-SESSION-RESPONSE."))
(defgeneric acp-load-session (agent request)
  (:documentation "session/load → LOAD-SESSION-RESPONSE, after replaying the
conversation as session/update notifications (capability loadSession)."))
(defgeneric acp-list-sessions (agent request)
  (:documentation "session/list → LIST-SESSIONS-RESPONSE."))
(defgeneric acp-delete-session (agent request)
  (:documentation "session/delete → DELETE-SESSION-RESPONSE."))
(defgeneric acp-resume-session (agent request)
  (:documentation "session/resume → RESUME-SESSION-RESPONSE (no replay)."))
(defgeneric acp-close-session (agent request)
  (:documentation "session/close → CLOSE-SESSION-RESPONSE."))
(defgeneric acp-set-session-mode (agent request)
  (:documentation "session/set_mode → SET-SESSION-MODE-RESPONSE."))
(defgeneric acp-set-session-config-option (agent request)
  (:documentation "session/set_config_option → SET-SESSION-CONFIG-OPTION-RESPONSE."))
(defgeneric acp-prompt (agent request)
  (:documentation "session/prompt → PROMPT-RESPONSE once the turn ends. Stream
progress meanwhile with ACP-SEND-UPDATE on *ACP-REMOTE*."))
(defgeneric acp-cancel (agent notification)
  (:documentation "session/cancel (notification): stop the session's turn; its
ACP-PROMPT then returns stopReason \"cancelled\"."))

;;; --- client-side GFs (agent → client) ----------------------------------------

(defgeneric acp-request-permission (client request)
  (:documentation "session/request_permission → REQUEST-PERMISSION-RESPONSE."))
(defgeneric acp-session-update (client notification)
  (:documentation "session/update (notification): one SESSION-NOTIFICATION."))
(defgeneric acp-read-text-file (client request)
  (:documentation "fs/read_text_file → READ-TEXT-FILE-RESPONSE."))
(defgeneric acp-write-text-file (client request)
  (:documentation "fs/write_text_file → WRITE-TEXT-FILE-RESPONSE."))
(defgeneric acp-create-terminal (client request)
  (:documentation "terminal/create → CREATE-TERMINAL-RESPONSE."))
(defgeneric acp-terminal-output (client request)
  (:documentation "terminal/output → TERMINAL-OUTPUT-RESPONSE."))
(defgeneric acp-release-terminal (client request)
  (:documentation "terminal/release → RELEASE-TERMINAL-RESPONSE."))
(defgeneric acp-wait-for-terminal-exit (client request)
  (:documentation "terminal/wait_for_exit → WAIT-FOR-TERMINAL-EXIT-RESPONSE."))
(defgeneric acp-kill-terminal (client request)
  (:documentation "terminal/kill → KILL-TERMINAL-RESPONSE."))
(defgeneric acp-create-elicitation (client request)
  (:documentation "elicitation/create → CREATE-ELICITATION-RESPONSE."))
(defgeneric acp-complete-elicitation (client notification)
  (:documentation "elicitation/complete (notification)."))

;;; --- both sides ---------------------------------------------------------------

(defgeneric acp-cancel-request (peer notification)
  (:documentation "$/cancel_request (notification). Cancellation is optional;
the default ignores it."))
(defgeneric acp-ext-method (peer method params)
  (:documentation "An extension request (METHOD starts with `_`): PARAMS and the
value are raw JSON. Default: ACP-METHOD-NOT-FOUND."))
(defgeneric acp-ext-notification (peer method params)
  (:documentation "An extension notification. Default: ignore."))

;;; --- defaults on the local classes -------------------------------------------

(defun %not-found (method)
  (error 'acp-method-not-found :method method
                               :message (format nil "Method not found: ~A" method)))

(defmacro %defaults (class &rest rows)
  `(progn
     ,@(loop for (gf method) in rows
             collect `(defmethod ,gf ((peer ,class) params)
                        (declare (ignore params))
                        (%not-found ,method)))))

(%defaults acp-agent
  (acp-initialize "initialize") (acp-authenticate "authenticate") (acp-logout "logout")
  (acp-new-session "session/new") (acp-load-session "session/load")
  (acp-list-sessions "session/list") (acp-delete-session "session/delete")
  (acp-resume-session "session/resume") (acp-close-session "session/close")
  (acp-set-session-mode "session/set_mode")
  (acp-set-session-config-option "session/set_config_option")
  (acp-prompt "session/prompt"))

(%defaults acp-client
  (acp-read-text-file "fs/read_text_file") (acp-write-text-file "fs/write_text_file")
  (acp-create-terminal "terminal/create") (acp-terminal-output "terminal/output")
  (acp-release-terminal "terminal/release")
  (acp-wait-for-terminal-exit "terminal/wait_for_exit") (acp-kill-terminal "terminal/kill")
  (acp-create-elicitation "elicitation/create"))

(defmethod acp-cancel ((agent acp-agent) notification)
  (declare (ignore notification))
  nil)

(defmethod acp-session-update ((client acp-client) notification)
  (declare (ignore notification))
  nil)

(defmethod acp-complete-elicitation ((client acp-client) notification)
  (declare (ignore notification))
  nil)

(defun %permission-response (outcome)
  (make-acp 'request-permission-response :outcome outcome))

(defmethod acp-request-permission ((client acp-client) request)
  (let* ((options (coerce (options request) 'list))
         (condition (make-condition 'acp-permission-required
                                    :request request :connection *acp-connection*)))
    (labels ((of-kind (kind) (find kind options :key #'kind :test #'equal))
             (offered-p (kind) (and (of-kind kind) t))
             (pick (option)
               (%permission-response
                (make-acp 'selected-permission-outcome :option-id (option-id option))))
             (cancelled () (%permission-response (make-acp 'cancelled-permission-outcome))))
      (or (restart-case (signal condition)
            (select-permission-option (option-id)
              :report "Answer with the option of this id."
              (pick (or (find option-id options :key #'option-id :test #'equal)
                        (error 'acp-invalid-params
                               :message (format nil "Unknown permission option id ~S" option-id)
                               :data (%json-object "optionId" option-id)))))
            (allow-once ()
              :report "Allow once." :test (lambda (c) (declare (ignore c)) (offered-p "allow_once"))
              (pick (of-kind "allow_once")))
            (allow-always ()
              :report "Allow always." :test (lambda (c) (declare (ignore c)) (offered-p "allow_always"))
              (pick (of-kind "allow_always")))
            (reject-once ()
              :report "Reject once." :test (lambda (c) (declare (ignore c)) (offered-p "reject_once"))
              (pick (of-kind "reject_once")))
            (reject-always ()
              :report "Reject always." :test (lambda (c) (declare (ignore c)) (offered-p "reject_always"))
              (pick (of-kind "reject_always")))
            (cancel-permission ()
              :report "Answer cancelled."
              (cancelled)))
          (cancelled)))))

(defmethod acp-cancel-request ((peer acp-peer) notification)
  (declare (ignore notification))
  nil)

(defmethod acp-ext-method ((peer acp-peer) method params)
  (declare (ignore params))
  (%not-found method))

(defmethod acp-ext-notification ((peer acp-peer) method params)
  (declare (ignore method params))
  nil)

;;; --- proxies: one line each onto REMOTE-CALL / REMOTE-NOTIFY ------------------

(defmacro %remote (class &rest rows)
  `(progn
     ,@(loop for (gf method kind) in rows
             collect `(defmethod ,gf ((peer ,class) params)
                        ,(if (eq kind :notification)
                             `(remote-notify peer ,method params)
                             `(remote-call peer ,method params))))))

(%remote remote-agent
  (acp-initialize "initialize") (acp-authenticate "authenticate") (acp-logout "logout")
  (acp-new-session "session/new") (acp-load-session "session/load")
  (acp-list-sessions "session/list") (acp-delete-session "session/delete")
  (acp-resume-session "session/resume") (acp-close-session "session/close")
  (acp-set-session-mode "session/set_mode")
  (acp-set-session-config-option "session/set_config_option")
  (acp-prompt "session/prompt")
  (acp-cancel "session/cancel" :notification)
  (acp-cancel-request "$/cancel_request" :notification))

(%remote remote-client
  (acp-request-permission "session/request_permission")
  (acp-session-update "session/update" :notification)
  (acp-read-text-file "fs/read_text_file") (acp-write-text-file "fs/write_text_file")
  (acp-create-terminal "terminal/create") (acp-terminal-output "terminal/output")
  (acp-release-terminal "terminal/release")
  (acp-wait-for-terminal-exit "terminal/wait_for_exit") (acp-kill-terminal "terminal/kill")
  (acp-create-elicitation "elicitation/create")
  (acp-complete-elicitation "elicitation/complete" :notification)
  (acp-cancel-request "$/cancel_request" :notification))

;;; REMOTE-AGENT's ACP-INITIALIZE and ACP-CANCEL and REMOTE-CLIENT's
;;; ACP-SESSION-UPDATE carry the extra bookkeeping documented above
;;; (recording the initialize exchange, counting cancels, the plan-operations
;;; check). They are :AROUND methods so the one-line proxies stay uniform.

(defmethod acp-initialize :around ((peer remote-agent) request)
  (let* ((response (call-next-method))
         (version (%slot-or-nil response 'protocol-version)))
    (unless (eql version +acp-protocol-version+)
      (error 'acp-version-mismatch
             :version version
             :message (format nil "The agent answered protocolVersion ~S; this build speaks ~D"
                              version +acp-protocol-version+)))
    (let ((connection (remote-connection peer))
          (request (if (hash-table-p request)
                       (parse-acp-object 'initialize-request request)
                       request)))
      (setf (acp-connection-client-capabilities connection)
            (%slot-or-nil request 'client-capabilities)
            (acp-connection-client-info connection) (%slot-or-nil request 'client-info)
            (acp-connection-protocol-version connection) version
            (acp-connection-agent-capabilities connection)
            (%slot-or-nil response 'agent-capabilities)
            (acp-connection-agent-info connection) (%slot-or-nil response 'agent-info)
            (acp-connection-initialized-p connection) t))
    response))

(defmethod acp-cancel :around ((peer remote-agent) notification)
  (let ((connection (remote-connection peer))
        (session-id (if (hash-table-p notification)
                        (gethash "sessionId" notification)
                        (session-id notification))))
    (bt2:with-lock-held ((acp-connection-lock connection))
      (incf (gethash session-id (acp-connection-cancel-counts connection) 0)))
    (call-next-method)))

(defmethod acp-session-update :around ((peer remote-client) notification)
  (let ((connection (remote-connection peer))
        (update (and (%schema-object-p notification) (%slot-or-nil notification 'update))))
    (when (and (typep update '(or update-plan-update update-plan-removed))
               (acp-connection-initialized-p connection)
               (not (client-supports-p (acp-connection-client-capabilities connection)
                                       :plan-operations)))
      (error 'acp-unsupported
             :method "session/update" :feature :plan-operations
             :message "The client did not advertise plan operations; send the full plan"))
    (call-next-method)))

;;; --- helpers -------------------------------------------------------------------

(defun acp-send-update (remote session-id update)
  (check-type remote remote-client)
  (acp-session-update remote (make-acp 'session-notification
                                       :session-id session-id :update update))
  t)

(defun %permission-option (option)
  (etypecase option
    (permission-option option)
    (list (destructuring-bind (option-id name kind) option
            (make-acp 'permission-option :option-id option-id :name name :kind kind)))))

(defun %kind-keyword (kind)
  (intern (string-upcase (substitute #\- #\_ kind)) :keyword))

(defun acp-ask-permission (remote session-id tool-call options)
  (check-type remote remote-client)
  (let* ((options (mapcar #'%permission-option options))
         (response (acp-request-permission
                    remote (make-acp 'request-permission-request
                                     :session-id session-id :tool-call tool-call
                                     :options (coerce options 'vector))))
         (outcome (outcome response)))
    (etypecase outcome
      (cancelled-permission-outcome (values :cancelled nil))
      (selected-permission-outcome
       (let* ((id (option-id outcome))
              (option (find id options :key #'option-id :test #'equal)))
         (unless option
           (error 'acp-internal-error
                  :message (format nil "The client chose option ~S, which was not offered" id)
                  :data (%json-object "optionId" id)))
         (values (%kind-keyword (kind option)) id))))))

(defun %check-extension (method)
  (unless (acp-extension-method-p method)
    (error 'acp-invalid-request
           :message (format nil "Not an extension method (must start with ~S): ~S"
                            +acp-extension-prefix+ method))))

(defun acp-call-ext (remote method params)
  (check-type remote remote-peer)
  (%check-extension method)
  (%remote-request remote method (%wire params)))

(defun acp-notify-ext (remote method params)
  (check-type remote remote-peer)
  (%check-extension method)
  (rpc-protocol:rpc-notify method (%wire params)
                           :transport (acp-connection-transport (remote-connection remote)))
  t)
