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

;;; Each feature is a path of wire keys into the dumped capabilities object,
;;; with the test its final value must pass: :TRUE (JSON true) or :OBJECT
;;; (a JSON object, `{}` = on). :ANY rows name other features.

(defparameter +%client-feature-paths+
  '((:read-text-file :true "fs" "readTextFile")
    (:write-text-file :true "fs" "writeTextFile")
    (:terminal :true "terminal")
    (:auth-terminal :true "auth" "terminal")
    (:plan-operations :object "plan")
    (:subagents :object "subagents")
    (:elicitation-form :object "elicitation" "form")
    (:elicitation-url :object "elicitation" "url")
    (:elicitation :any :elicitation-form :elicitation-url)
    (:boolean-config-options :object "session" "configOptions" "boolean")
    (:session-compaction :object "session" "compaction")
    (:session-notices :object "session" "notices")))

(defparameter +%agent-feature-paths+
  '((:load-session :true "loadSession")
    (:image :true "promptCapabilities" "image")
    (:audio :true "promptCapabilities" "audio")
    (:embedded-context :true "promptCapabilities" "embeddedContext")
    (:mcp-http :true "mcpCapabilities" "http")
    (:mcp-sse :true "mcpCapabilities" "sse")
    (:session-list :object "sessionCapabilities" "list")
    (:session-delete :object "sessionCapabilities" "delete")
    (:session-resume :object "sessionCapabilities" "resume")
    (:session-close :object "sessionCapabilities" "close")
    (:additional-directories :object "sessionCapabilities" "additionalDirectories")
    (:system-prompt :object "sessionCapabilities" "systemPrompt")
    (:logout :object "auth" "logout")))

(assert (null (set-exclusive-or (mapcar #'first +%client-feature-paths+) +acp-client-features+)))
(assert (null (set-exclusive-or (mapcar #'first +%agent-feature-paths+) +acp-agent-features+)))

(defun %json-path (node keys)
  (dolist (key keys node)
    (setf node (and (hash-table-p node) (gethash key node)))))

(defun %supports-p (caps feature rows)
  (let ((row (assoc feature rows)))
    (unless row
      (error 'type-error :datum feature
                         :expected-type `(member ,@(mapcar #'first rows))))
    (when (or (hash-table-p caps) (%schema-object-p caps))
      (destructuring-bind (test &rest keys) (rest row)
        (if (eq test :any)
            (some (lambda (f) (%supports-p caps f rows)) keys)
            (let ((value (%json-path (acp-object-table caps) keys)))
              (ecase test
                (:true (eq value t))
                (:object (hash-table-p value)))))))))

(defun client-supports-p (caps feature)
  (%supports-p caps feature +%client-feature-paths+))

(defun agent-supports-p (caps feature)
  (%supports-p caps feature +%agent-feature-paths+))

(defun capability-meta (caps key)
  (let ((meta (cond ((hash-table-p caps) (gethash "_meta" caps))
                    ((and (%schema-object-p caps)
                          (slot-exists-p caps 'meta)
                          (slot-boundp caps 'meta))
                     (meta caps)))))
    (if (hash-table-p meta)
        (gethash key meta)
        (values nil nil))))
