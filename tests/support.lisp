(in-package #:acp-protocol/tests)

;;; Shared helpers: vendored fixtures, JSON equality, a scripted test agent and
;;; a recording test client for the loopback pair.

(defparameter *fixtures*
  (asdf:system-relative-pathname "acp-protocol" "tests/fixtures/v1/"))

(defun fixture-text (name)
  (uiop:read-file-string (merge-pathnames name *fixtures*)))

(defun fixture-json (name)
  (json-protocol:decode (fixture-text name)))

(defun json (text)
  (json-protocol:decode text))

(defun js (&rest kvs)
  "A JSON object (EQUAL hash-table) from alternating keys and values."
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kvs by #'cddr do (setf (gethash k h) v))
    h))

(defun json-equal (a b)
  "Structural JSON equality: objects by key set, arrays elementwise."
  (cond
    ((and (hash-table-p a) (hash-table-p b))
     (and (= (hash-table-count a) (hash-table-count b))
          (loop for k being the hash-keys of a using (hash-value v)
                always (multiple-value-bind (w found) (gethash k b)
                         (and found (json-equal v w))))))
    ((and (stringp a) (stringp b)) (string= a b))
    ((and (vectorp a) (vectorp b))
     (and (= (length a) (length b)) (every #'json-equal a b)))
    ((and (numberp a) (numberp b)) (= a b))
    (t (eql a b))))

(defun same-json-text-p (a b)
  "Are the JSON texts A and B (or decoded values) structurally equal?"
  (json-equal (if (stringp a) (json a) a) (if (stringp b) (json b) b)))

(defun object-json-p (object expected-text)
  "Does OBJECT dump to the JSON of EXPECTED-TEXT?"
  (json-equal (acp:acp-object-table object) (json expected-text)))

(defun log-lines (remote &optional direction)
  "The loopback log texts, oldest first, optionally only one DIRECTION."
  (loop for (dir . text) in (acp:acp-loopback-log remote)
        when (or (null direction) (eq dir direction)) collect text))

(defun line-method (text)
  (let ((v (json text)))
    (and (hash-table-p v) (gethash "method" v))))

(defun count-method-lines (remote method)
  (count method (log-lines remote) :key #'line-method :test #'equal))

;;; --- test agent ------------------------------------------------------------------

(defclass test-agent (acp:acp-agent)
  ((caps :initarg :caps :initform nil :accessor agent-caps
         :documentation "AGENT-CAPABILITIES to answer, or NIL.")
   (version :initarg :version :initform nil :accessor agent-version
            :documentation "protocolVersion to answer; NIL leaves it to the dispatcher.")
   (events :initform '() :accessor agent-events :documentation "Newest first.")
   (sessions :initform '() :accessor agent-sessions)
   (cancelled :initform '() :accessor agent-cancelled)
   (script :initarg :script :initform nil :accessor agent-script
           :documentation "(lambda (agent request)) → PROMPT-RESPONSE for session/prompt.")
   (failures :initarg :failures :initform 0 :accessor agent-failures
             :documentation "session/set_mode signals this many times before it succeeds.")
   (seen :initform '() :accessor agent-seen
         :documentation "(*acp-connection* . *acp-remote*) seen in the last GF.")))

(defun note (agent &rest event)
  (push event (agent-events agent)))

(defun agent-event (agent key)
  (find key (agent-events agent) :key #'first))

(defun %session-or-fail (agent id)
  (unless (member id (agent-sessions agent) :test #'equal)
    (error 'acp:acp-resource-not-found :message "Resource not found"
                                       :data (js "sessionId" id))))

(defmethod acp:acp-initialize ((agent test-agent) request)
  (setf (agent-seen agent) (cons acp:*acp-connection* acp:*acp-remote*))
  (note agent :initialize request)
  (let ((r (acp:make-acp 'acp:initialize-response
                         :agent-capabilities (agent-caps agent)
                         :agent-info (acp:make-acp 'acp:implementation
                                                   :name "test-agent" :version "0.0.1"))))
    (when (agent-version agent)
      (setf (acp:protocol-version r) (agent-version agent)))
    r))

(defmethod acp:acp-authenticate ((agent test-agent) request)
  (note agent :authenticate (acp:method-id request))
  (if (equal (acp:method-id request) "agent-login")
      (acp:make-acp 'acp:authenticate-response)
      (error 'acp:acp-auth-required)))

(defmethod acp:acp-new-session ((agent test-agent) request)
  (let ((id (format nil "sess-~D" (1+ (length (agent-sessions agent))))))
    (push id (agent-sessions agent))
    (note agent :new-session (acp:cwd request))
    (acp:make-acp 'acp:new-session-response
                  :session-id id
                  :modes (acp:make-acp
                          'acp:session-mode-state
                          :current-mode-id "ask"
                          :available-modes
                          (vector (acp:make-acp 'acp:session-mode :id "ask" :name "Ask")
                                  (acp:make-acp 'acp:session-mode :id "code" :name "Code"))))))

(defmethod acp:acp-load-session ((agent test-agent) request)
  (let ((id (acp:session-id request)))
    (push id (agent-sessions agent))
    (acp:acp-send-update acp:*acp-remote* id
                         (acp:make-acp 'acp:update-user-message-chunk
                                       :content (acp:make-acp 'acp:text-content :text "earlier")))
    (acp:acp-send-update acp:*acp-remote* id
                         (acp:make-acp 'acp:update-agent-message-chunk
                                       :content (acp:make-acp 'acp:text-content :text "reply")))
    (acp:make-acp 'acp:load-session-response)))

(defmethod acp:acp-set-session-mode ((agent test-agent) request)
  (%session-or-fail agent (acp:session-id request))
  (when (plusp (agent-failures agent))
    (decf (agent-failures agent))
    (error 'acp:acp-request-cancelled))
  (acp:acp-send-update acp:*acp-remote* (acp:session-id request)
                       (acp:make-acp 'acp:update-current-mode-update
                                     :current-mode-id (acp:mode-id request)))
  (acp:make-acp 'acp:set-session-mode-response))

(defmethod acp:acp-prompt ((agent test-agent) request)
  (setf (agent-seen agent) (cons acp:*acp-connection* acp:*acp-remote*))
  (%session-or-fail agent (acp:session-id request))
  (note agent :prompt (acp:session-id request))
  (if (agent-script agent)
      (funcall (agent-script agent) agent request)
      (acp:make-acp 'acp:prompt-response :stop-reason "end_turn")))

(defmethod acp:acp-cancel ((agent test-agent) notification)
  (push (acp:session-id notification) (agent-cancelled agent))
  (note agent :cancel (acp:session-id notification)))

(defmethod acp:acp-cancel-request ((agent test-agent) notification)
  (note agent :cancel-request (acp:request-id notification)))

(defmethod acp:acp-ext-method ((agent test-agent) method params)
  (if (equal method "_cl-stack.test/echo")
      (js "echo" params)
      (call-next-method)))

(defmethod acp:acp-ext-notification ((agent test-agent) method params)
  (note agent :ext-notification method params))

;;; --- test client -----------------------------------------------------------------

(defclass test-client (acp:acp-client)
  ((updates :initform '() :accessor client-updates :documentation "Newest first.")
   (files :initform (make-hash-table :test 'equal) :reader client-files)
   (calls :initform '() :accessor client-calls :documentation "Method names, newest first.")
   (elicitations :initform '() :accessor client-elicitations)))

(defun client-update-objects (client)
  "The UPDATE of every received session/update, oldest first."
  (mapcar #'acp:update (reverse (client-updates client))))

(defmethod acp:acp-session-update ((client test-client) notification)
  (push notification (client-updates client)))

(defmethod acp:acp-read-text-file ((client test-client) request)
  (push "fs/read_text_file" (client-calls client))
  (let ((text (gethash (acp:path request) (client-files client))))
    (unless text
      (error 'acp:acp-resource-not-found :data (js "path" (acp:path request))))
    (acp:make-acp 'acp:read-text-file-response :content text)))

(defmethod acp:acp-write-text-file ((client test-client) request)
  (push "fs/write_text_file" (client-calls client))
  (setf (gethash (acp:path request) (client-files client)) (acp:content request))
  (acp:make-acp 'acp:write-text-file-response))

(defmethod acp:acp-create-terminal ((client test-client) request)
  (push "terminal/create" (client-calls client))
  (acp:make-acp 'acp:create-terminal-response
                :terminal-id (format nil "term-~A" (acp:command request))))

(defmethod acp:acp-terminal-output ((client test-client) request)
  (declare (ignore request))
  (push "terminal/output" (client-calls client))
  (make-instance 'acp:terminal-output-response
                 :output "ok" :truncated nil
                 :exit-status (acp:make-acp 'acp:terminal-exit-status :exit-code 0)))

(defmethod acp:acp-wait-for-terminal-exit ((client test-client) request)
  (declare (ignore request))
  (push "terminal/wait_for_exit" (client-calls client))
  (acp:make-acp 'acp:wait-for-terminal-exit-response :exit-code 0))

(defmethod acp:acp-release-terminal ((client test-client) request)
  (declare (ignore request))
  (push "terminal/release" (client-calls client))
  (acp:make-acp 'acp:release-terminal-response))

(defmethod acp:acp-create-elicitation ((client test-client) request)
  (push (acp:message request) (client-elicitations client))
  (acp:make-acp 'acp:create-elicitation-response
                :action "accept" :content (js "name" "Ada")))

(defmethod acp:acp-complete-elicitation ((client test-client) notification)
  (push (list :complete (acp:elicitation-id notification)) (client-elicitations client)))

;;; --- pairs -------------------------------------------------------------------------

(defun client-caps (text)
  (acp:parse-acp-object 'acp:client-capabilities (json text)))

(defun agent-caps-from (text)
  (acp:parse-acp-object 'acp:agent-capabilities (json text)))

(defparameter *full-client-caps*
  "{\"fs\":{\"readTextFile\":true,\"writeTextFile\":true},\"terminal\":true,
    \"plan\":{},\"elicitation\":{\"form\":{}}}")

(defun pair (&key script (agent-caps "{\"loadSession\":true}") version failures)
  "→ (values remote-agent remote-client agent client), not initialized."
  (let ((agent (make-instance 'test-agent
                              :script script :version version
                              :failures (or failures 0)
                              :caps (and agent-caps (agent-caps-from agent-caps))))
        (client (make-instance 'test-client)))
    (multiple-value-bind (ra rc) (acp:make-acp-loopback agent client)
      (values ra rc agent client))))

(defun initialize (ra &key (caps *full-client-caps*))
  (acp:acp-initialize ra (acp:make-acp 'acp:initialize-request
                                       :protocol-version 1
                                       :client-capabilities (and caps (client-caps caps))
                                       :client-info (acp:make-acp 'acp:implementation
                                                                  :name "test-client"
                                                                  :version "0.0.1"))))

(defun new-session (ra)
  (acp:session-id (acp:acp-new-session ra (acp:make-acp 'acp:new-session-request
                                                        :cwd "/work" :mcp-servers #()))))

(defun prompt (ra session-id text)
  (acp:acp-prompt ra (acp:make-acp 'acp:prompt-request
                                   :session-id session-id
                                   :prompt (vector (acp:make-acp 'acp:text-content :text text)))))

(defun session-of (&key (caps *full-client-caps*) script failures
                     (agent-caps "{\"loadSession\":true}"))
  "A pair, initialized, with one session: → (values ra rc agent client session-id)."
  (multiple-value-bind (ra rc agent client)
      (pair :script script :failures failures :agent-caps agent-caps)
    (initialize ra :caps caps)
    (values ra rc agent client (new-session ra))))

(defun tool-call-update (id &rest initargs)
  (apply #'acp:make-acp 'acp:tool-call-update :tool-call-id id initargs))

(defun options (&rest kinds)
  "Permission options, one per kind string, ids = the kinds."
  (mapcar (lambda (k) (acp:make-acp 'acp:permission-option :option-id k :name k :kind k))
          kinds))

(defun d (x)
  "A Rove description string for any value."
  (princ-to-string x))
