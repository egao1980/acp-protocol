(in-package #:acp-protocol)

;;; Constants and the method table (GIVEN, contract ACP-0).

(defconstant +acp-protocol-version+ 1
  "The ACP major protocol version (initialize protocolVersion).")

(defparameter +acp-schema-version+ "1.34.1"
  "The pinned stable schema release (agentclientprotocol/agent-client-protocol
tag schema-v1.34.1, schema/v1/schema.json).")

(defparameter +acp-extension-prefix+ "_"
  "Method names starting with this are extension methods (spec Extensibility).")

(defparameter +acp-stop-reasons+
  '("end_turn" "max_tokens" "max_turn_requests" "refusal" "cancelled"))

(defparameter +acp-tool-kinds+
  '("read" "edit" "delete" "move" "search" "execute" "think" "fetch" "switch_mode" "other"))

(defparameter +acp-tool-call-statuses+ '("pending" "in_progress" "completed" "failed"))

(defparameter +acp-permission-option-kinds+
  '("allow_once" "allow_always" "reject_once" "reject_always"))

;;; One row per method: (METHOD DIRECTION KIND REQUEST-CLASS RESPONSE-CLASS GF
;;; CAPABILITY).
;;;   DIRECTION  :agent  = sent by the client, handled by the agent
;;;              :client = sent by the agent, handled by the client
;;;              :both   = either side ($/cancel_request)
;;;   KIND       :request | :notification (RESPONSE-CLASS NIL)
;;;   GF         the generic function the receiving side's dispatcher calls,
;;;              (GF local-peer params-object); for :notification its value
;;;              is ignored
;;;   CAPABILITY NIL (always available) or the feature keyword the RECEIVER
;;;              must have advertised at initialize (AGENT-SUPPORTS-P /
;;;              CLIENT-SUPPORTS-P); a sender refuses an unadvertised method
;;;              locally with ACP-UNSUPPORTED.
(defparameter +acp-methods+
  '(("initialize" :agent :request initialize-request initialize-response acp-initialize nil)
    ("authenticate" :agent :request authenticate-request authenticate-response acp-authenticate nil)
    ("logout" :agent :request logout-request logout-response acp-logout :logout)
    ("session/new" :agent :request new-session-request new-session-response acp-new-session nil)
    ("session/load" :agent :request load-session-request load-session-response acp-load-session :load-session)
    ("session/list" :agent :request list-sessions-request list-sessions-response acp-list-sessions :session-list)
    ("session/delete" :agent :request delete-session-request delete-session-response acp-delete-session :session-delete)
    ("session/resume" :agent :request resume-session-request resume-session-response acp-resume-session :session-resume)
    ("session/close" :agent :request close-session-request close-session-response acp-close-session :session-close)
    ("session/set_mode" :agent :request set-session-mode-request set-session-mode-response acp-set-session-mode nil)
    ("session/set_config_option" :agent :request set-session-config-option-request
     set-session-config-option-response acp-set-session-config-option nil)
    ("session/prompt" :agent :request prompt-request prompt-response acp-prompt nil)
    ("session/cancel" :agent :notification cancel-notification nil acp-cancel nil)
    ("session/request_permission" :client :request request-permission-request
     request-permission-response acp-request-permission nil)
    ("session/update" :client :notification session-notification nil acp-session-update nil)
    ("fs/read_text_file" :client :request read-text-file-request read-text-file-response
     acp-read-text-file :read-text-file)
    ("fs/write_text_file" :client :request write-text-file-request write-text-file-response
     acp-write-text-file :write-text-file)
    ("terminal/create" :client :request create-terminal-request create-terminal-response
     acp-create-terminal :terminal)
    ("terminal/output" :client :request terminal-output-request terminal-output-response
     acp-terminal-output :terminal)
    ("terminal/release" :client :request release-terminal-request release-terminal-response
     acp-release-terminal :terminal)
    ("terminal/wait_for_exit" :client :request wait-for-terminal-exit-request
     wait-for-terminal-exit-response acp-wait-for-terminal-exit :terminal)
    ("terminal/kill" :client :request kill-terminal-request kill-terminal-response
     acp-kill-terminal :terminal)
    ("elicitation/create" :client :request create-elicitation-request create-elicitation-response
     acp-create-elicitation :elicitation)
    ("elicitation/complete" :client :notification complete-elicitation-notification nil
     acp-complete-elicitation nil)
    ("$/cancel_request" :both :notification cancel-request-notification nil acp-cancel-request nil))
  "Every stable ACP v1 method (schema/v1/meta.json of schema-v1.34.1).")

(defun acp-method-row (method)
  "The +ACP-METHODS+ row of METHOD (a string), or NIL."
  (assoc method +acp-methods+ :test #'string=))

(defun acp-method-direction (method) (second (acp-method-row method)))
(defun acp-method-kind (method) (third (acp-method-row method)))
(defun acp-method-request-class (method) (fourth (acp-method-row method)))
(defun acp-method-response-class (method) (fifth (acp-method-row method)))
(defun acp-method-function (method) (sixth (acp-method-row method)))
(defun acp-method-capability (method) (seventh (acp-method-row method)))

(defun acp-extension-method-p (method)
  "Is METHOD an extension method name (starts with `_`)?"
  (and (stringp method)
       (plusp (length method))
       (string= +acp-extension-prefix+ method :end2 1)))

;;; Features for CLIENT-SUPPORTS-P / AGENT-SUPPORTS-P (capabilities.lisp).
(defparameter +acp-client-features+
  '(:read-text-file :write-text-file :terminal :auth-terminal :plan-operations
    :elicitation :elicitation-form :elicitation-url :boolean-config-options
    :session-compaction :session-notices :subagents))

(defparameter +acp-agent-features+
  '(:load-session :image :audio :embedded-context :mcp-http :mcp-sse
    :session-list :session-delete :session-resume :session-close
    :additional-directories :system-prompt :logout))
