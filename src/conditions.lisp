(in-package #:acp-protocol)

;;; Conditions and restarts (GIVEN, contract ACP-0; ACP-ERROR-FOR and
;;; ACP-CONDITION-FOR are stubs in codec.lisp).
;;;
;;; One condition per ACP error code (spec "Errors", schema ErrorCode). A
;;; handler on the receiving side signals one of these; the dispatcher answers
;;; with its code, message and data. The calling side turns an error response
;;; back into the condition of that code (ACP-CONDITION-FOR); a code it does
;;; not know becomes a plain ACP-ERROR with that code (the spec: "treat an
;;; unrecognized code as a generic failure").
;;;
;;;   code    condition                  when
;;;   -32600  acp-invalid-request        a request before initialize; a bad envelope
;;;   -32601  acp-method-not-found       unknown method, or not implemented
;;;   -32601  acp-unsupported            the receiver did not advertise the capability
;;;                                      (signalled locally by the sender; on the wire
;;;                                      it is a -32601 and comes back as
;;;                                      ACP-METHOD-NOT-FOUND)
;;;   -32602  acp-invalid-params         params that do not parse, unknown mode / config id
;;;   -32603  acp-internal-error         any other error in a handler; a malformed result
;;;   -32800  acp-request-cancelled      the request was cancelled
;;;   -32000  acp-auth-required          authenticate first
;;;   -32002  acp-resource-not-found     unknown session / file / terminal (DATA names it)
;;;   (local) acp-version-mismatch       the agent answered initialize with a version
;;;                                      this build does not speak (code -32600)
;;;
;;; ACP-PERMISSION-REQUIRED is not an error: the default client method for
;;; session/request_permission SIGNALs it with the restarts below, so a
;;; HANDLER-BIND picks the answer, as ai-agent-protocol's
;;; AGENT-APPROVAL-REQUIRED does for approvals. Declining to handle it (the
;;; signal returns) answers `cancelled`.

(define-condition acp-error (error)
  ((code :initarg :code :reader acp-error-code :initform -32603)
   (message :initarg :message :reader acp-error-message :initform "ACP error")
   (data :initarg :data :reader acp-error-data :initform nil
         :documentation "The JSON-RPC error data (a hash-table, any JSON value, or NIL).")
   (cause :initarg :cause :reader acp-error-cause :initform nil))
  (:report (lambda (c s)
             (format s "~A [~A]" (acp-error-message c) (acp-error-code c)))))

(define-condition acp-invalid-request (acp-error) ()
  (:default-initargs :code -32600 :message "Invalid request"))

(define-condition acp-method-not-found (acp-error)
  ((method :initarg :method :reader acp-error-method :initform nil))
  (:default-initargs :code -32601 :message "Method not found"))

(define-condition acp-unsupported (acp-method-not-found)
  ((feature :initarg :feature :reader acp-unsupported-feature :initform nil))
  (:default-initargs :message "Capability not advertised by the peer")
  (:report (lambda (c s)
             (format s "~A~@[ (~A)~]~@[: ~S~] [~A]"
                     (acp-error-message c) (acp-error-method c)
                     (acp-unsupported-feature c) (acp-error-code c)))))

(define-condition acp-invalid-params (acp-error) ()
  (:default-initargs :code -32602 :message "Invalid params"))

(define-condition acp-internal-error (acp-error) ()
  (:default-initargs :code -32603 :message "Internal error"))

(define-condition acp-request-cancelled (acp-error) ()
  (:default-initargs :code -32800 :message "Request cancelled"))

(define-condition acp-auth-required (acp-error) ()
  (:default-initargs :code -32000 :message "Authentication required"))

(define-condition acp-resource-not-found (acp-error) ()
  (:default-initargs :code -32002 :message "Resource not found"))

(define-condition acp-version-mismatch (acp-error)
  ((version :initarg :version :reader acp-version-mismatch-version :initform nil))
  (:default-initargs :code -32600 :message "Unsupported ACP protocol version"))

(defparameter +acp-error-codes+
  '((acp-request-cancelled . -32800)
    (acp-auth-required . -32000)
    (acp-resource-not-found . -32002)
    (acp-invalid-request . -32600)
    (acp-method-not-found . -32601)
    (acp-invalid-params . -32602)
    (acp-internal-error . -32603))
  "Condition type → code. ACP-CONDITION-FOR maps a code to the FIRST row with
that code (so -32601 → ACP-METHOD-NOT-FOUND, never ACP-UNSUPPORTED).")

;;; --- permission -------------------------------------------------------------

(define-condition acp-permission-required (condition)
  ((request :initarg :request :reader acp-permission-required-request
            :documentation "The REQUEST-PERMISSION-REQUEST.")
   (connection :initarg :connection :reader acp-permission-required-connection
               :initform nil))
  (:report (lambda (c s)
             (let ((r (acp-permission-required-request c)))
               (format s "ACP permission required~@[ for ~S~]"
                       (ignore-errors (title (tool-call r)))))))
  (:documentation
   "Signalled (not an error) by the default ACP-REQUEST-PERMISSION method.
Restarts, live while the signal runs:
  SELECT-PERMISSION-OPTION (option-id)  answer with that option
  ALLOW-ONCE / ALLOW-ALWAYS / REJECT-ONCE / REJECT-ALWAYS
                                        answer with the first option of that
                                        kind; each restart is visible only when
                                        the request offers such an option
  CANCEL-PERMISSION                     answer `cancelled`
No handler (the signal returns) → `cancelled`."))

(defun %invoke (name condition &rest args)
  (let ((r (find-restart name condition)))
    (when r (apply #'invoke-restart r args))))

(defun invoke-select-permission-option (option-id &optional condition)
  (%invoke 'select-permission-option condition option-id))

(defun invoke-allow-once (&optional condition) (%invoke 'allow-once condition))
(defun invoke-allow-always (&optional condition) (%invoke 'allow-always condition))
(defun invoke-reject-once (&optional condition) (%invoke 'reject-once condition))
(defun invoke-reject-always (&optional condition) (%invoke 'reject-always condition))
(defun invoke-cancel-permission (&optional condition) (%invoke 'cancel-permission condition))

;;; --- calling-side restarts ----------------------------------------------------
;;; REMOTE-CALL (peer.lisp) establishes RETRY (send the request again) and
;;; USE-VALUE (return the given response object instead) around a call whose
;;; error response it re-signals as a condition.

(defun invoke-retry (&optional condition) (%invoke 'retry condition))

(defun invoke-use-value (value &optional condition) (%invoke 'use-value condition value))
