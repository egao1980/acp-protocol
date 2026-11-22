(in-package #:acp-protocol)

;;; Capability queries (contract ACP-0; STUBBED).
;;;
;;; The spec: every capability is optional, and an omitted one MUST be
;;; treated as UNSUPPORTED. Capability objects whose only content is _meta are
;;; on when present as an object (`{}`), off when absent or null. Unknown
;;; fields in a capability object are ignored (they stay in its extras).
;;;
;;; CLIENT-SUPPORTS-P CAPS FEATURE → generalized boolean. CAPS is a
;;;   CLIENT-CAPABILITIES (or NIL = nothing advertised). FEATURE is one of
;;;   +ACP-CLIENT-FEATURES+:
;;;     :read-text-file :write-text-file  fs.readTextFile / fs.writeTextFile true
;;;     :terminal                         terminal true
;;;     :auth-terminal                    auth.terminal true
;;;     :plan-operations                  plan is an object
;;;     :elicitation-form / -url          elicitation.form / .url is an object
;;;     :elicitation                      either of the two
;;;     :boolean-config-options           session.configOptions.boolean is an object
;;;     :session-compaction / -notices    session.compaction / .notices is an object
;;;     :subagents                        subagents is an object
;;; AGENT-SUPPORTS-P CAPS FEATURE: CAPS an AGENT-CAPABILITIES (or NIL);
;;;   FEATURE one of +ACP-AGENT-FEATURES+:
;;;     :load-session                     loadSession true
;;;     :image :audio :embedded-context   promptCapabilities.* true
;;;     :mcp-http :mcp-sse                mcpCapabilities.http / .sse true
;;;     :session-list :session-delete :session-resume :session-close
;;;     :additional-directories :system-prompt
;;;                                       sessionCapabilities.* is an object
;;;     :logout                           auth.logout is an object
;;; Any other FEATURE signals a TYPE-ERROR (a programming error, not a wire one).
;;; CAPABILITY-META CAPS KEY → (values value present-p): KEY in the `_meta`
;;;   object of CAPS (any model object with a META slot); how extensions
;;;   advertise themselves ("com.example/workspace"). NIL NIL when absent.

(defun client-supports-p (caps feature)
  (declare (ignore caps feature))
  (%acp0-pending 'client-supports-p))

(defun agent-supports-p (caps feature)
  (declare (ignore caps feature))
  (%acp0-pending 'agent-supports-p))

(defun capability-meta (caps key)
  (declare (ignore caps key))
  (%acp0-pending 'capability-meta))
