(in-package #:acp-protocol/tests)

;;; The loopback pair: a scripted TEST-AGENT and a recording TEST-CLIENT in one
;;; image, every message crossing as JSON-RPC text. initialize → session/new →
;;; a prompt that streams updates, asks permission, reads and writes files and
;;; runs a terminal → cancel; capability gating; errors as conditions.

(defun %update-tags (client)
  (mapcar #'acp:session-update (client-update-objects client)))

(defun %text (s) (acp:make-acp 'acp:text-content :text s))

(defun %end (&optional (reason "end_turn"))
  (acp:make-acp 'acp:prompt-response :stop-reason reason))

;;; --- initialize -------------------------------------------------------------------

(deftest loopback-initialize-records-both-sides
  (multiple-value-bind (ra rc agent) (pair)
    (let ((res (initialize ra)))
      (ok (typep res 'acp:initialize-response))
      (ok (eql 1 (acp:protocol-version res)) "the dispatcher fills an unbound version")
      (ok (equal "test-agent" (acp:name (acp:agent-info res))))
      (let ((cc (acp:remote-connection ra))   ; the client side
            (ac (acp:remote-connection rc)))  ; the agent side
        (ok (eq :client (acp:acp-connection-role cc)))
        (ok (eq :agent (acp:acp-connection-role ac)))
        (ok (eq ra (acp:acp-connection-remote cc)))
        (ok (eq rc (acp:acp-connection-remote ac)))
        (ok (acp:acp-connection-initialized-p cc))
        (ok (acp:acp-connection-initialized-p ac))
        (ok (eql 1 (acp:acp-connection-protocol-version cc)))
        (ok (eql 1 (acp:acp-connection-protocol-version ac)))
        (ok (acp:agent-supports-p (acp:acp-connection-agent-capabilities cc) :load-session))
        (ok (acp:client-supports-p (acp:acp-connection-client-capabilities ac) :terminal))
        (ok (equal "test-client" (acp:name (acp:acp-connection-client-info ac))))
        (ok (equal "test-agent" (acp:name (acp:acp-connection-agent-info cc))))
        (ok (eq ac (car (agent-seen agent))) "*acp-connection* is the agent side")
        (ok (eq rc (cdr (agent-seen agent))) "*acp-remote* is the client proxy")))
    (ok (typep (second (agent-event agent :initialize)) 'acp:initialize-request))))

(deftest loopback-initialize-on-the-wire
  (let ((ra (pair)))
    (initialize ra)
    (let ((log (acp:acp-loopback-log ra)))
      (ok (= 2 (length log)))
      (ok (eq :to-agent (car (first log))))
      (ok (eq :to-client (car (second log))))
      (ok (equal "initialize" (line-method (cdr (first log)))))
      (ok (equal "2.0" (gethash "jsonrpc" (json (cdr (first log))))))
      (ok (eql 1 (gethash "protocolVersion" (gethash "result" (json (cdr (second log))))))))))

(deftest loopback-version-negotiation
  (let ((ra (pair :version 1)))
    (ok (eql 1 (acp:protocol-version (initialize ra)))))
  (let ((ra (pair :version 2)))
    (let ((c (handler-case (initialize ra) (acp:acp-version-mismatch (c) c))))
      (ok (typep c 'acp:acp-version-mismatch))
      (ok (eql 2 (acp:acp-version-mismatch-version c))))))

(deftest loopback-request-before-initialize
  (multiple-value-bind (ra rc agent) (pair)
    (declare (ignore rc))
    (ok (signals (new-session ra) 'acp:acp-invalid-request))
    (ok (null (agent-event agent :new-session)))))

;;; --- one full turn ------------------------------------------------------------------

(defun %work-script (agent request)
  "Stream text and thought, a tool call that needs permission, file and terminal
round trips, a diff, a plan, commands; then end the turn."
  (let ((rc acp:*acp-remote*) (sid (acp:session-id request)))
    (acp:acp-send-update rc sid (acp:make-acp 'acp:update-agent-message-chunk
                                              :content (%text "Looking")))
    (acp:acp-send-update rc sid (acp:make-acp 'acp:update-agent-thought-chunk
                                              :content (%text "need to read")))
    (acp:acp-send-update rc sid (acp:make-acp 'acp:update-tool-call
                                              :tool-call-id "t1" :title "Edit a.txt"
                                              :kind "edit" :status "pending"))
    (multiple-value-bind (kind option)
        (acp:acp-ask-permission rc sid (tool-call-update "t1" :title "Edit a.txt")
                                (options "allow_once" "allow_always" "reject_once"))
      (note agent :permission kind option))
    (let ((old (acp:content (acp:acp-read-text-file
                             rc (acp:make-acp 'acp:read-text-file-request
                                              :session-id sid :path "/w/a.txt")))))
      (note agent :read old)
      (acp:acp-write-text-file rc (acp:make-acp 'acp:write-text-file-request
                                                :session-id sid :path "/w/a.txt"
                                                :content "new"))
      (let* ((tid (acp:terminal-id (acp:acp-create-terminal
                                    rc (acp:make-acp 'acp:create-terminal-request
                                                     :session-id sid :command "make"))))
             (out (acp:acp-terminal-output rc (acp:make-acp 'acp:terminal-output-request
                                                            :session-id sid :terminal-id tid)))
             (exit (acp:acp-wait-for-terminal-exit
                    rc (acp:make-acp 'acp:wait-for-terminal-exit-request
                                     :session-id sid :terminal-id tid))))
        (note agent :terminal tid (acp:output out) (acp:truncated out) (acp:exit-code exit))
        (acp:acp-release-terminal rc (acp:make-acp 'acp:release-terminal-request
                                                   :session-id sid :terminal-id tid))
        (acp:acp-send-update rc sid
                             (acp:make-acp 'acp:update-tool-call-update
                                           :tool-call-id "t1" :status "completed"
                                           :content (vector (acp:make-acp 'acp:diff :path "/w/a.txt"
                                                                                    :old-text old
                                                                                    :new-text "new")
                                                            (acp:make-acp 'acp:terminal
                                                                          :terminal-id tid))))))
    (acp:acp-send-update rc sid
                         (acp:make-acp 'acp:update-plan
                                       :entries (vector (acp:make-acp 'acp:plan-entry
                                                                      :content "edit a.txt"
                                                                      :priority "high"
                                                                      :status "completed"))))
    (acp:acp-send-update rc sid
                         (acp:make-acp 'acp:update-available-commands-update
                                       :available-commands
                                       (vector (acp:make-acp 'acp:available-command
                                                             :name "test" :description "run tests"))))
    (%end)))

(deftest loopback-full-turn
  (multiple-value-bind (ra rc agent client sid) (session-of :script #'%work-script)
    (declare (ignore rc))
    (setf (gethash "/w/a.txt" (client-files client)) "old")
    (let ((res (handler-bind ((acp:acp-permission-required
                                (lambda (c)
                                  (ok (equal sid (acp:session-id (acp:acp-permission-required-request c))))
                                  (acp:invoke-allow-once c))))
                 (prompt ra sid "fix a.txt"))))
      (ok (typep res 'acp:prompt-response))
      (ok (equal "end_turn" (acp:stop-reason res))))
    (ok (equal '(:permission :allow-once "allow_once") (agent-event agent :permission)))
    (ok (equal '(:read "old") (agent-event agent :read)))
    (ok (equal "new" (gethash "/w/a.txt" (client-files client))))
    (ok (equal '(:terminal "term-make" "ok" nil 0) (agent-event agent :terminal)))
    (ok (equal '("fs/read_text_file" "fs/write_text_file" "terminal/create" "terminal/output"
                 "terminal/wait_for_exit" "terminal/release")
               (reverse (client-calls client))))
    (ok (equal '("agent_message_chunk" "agent_thought_chunk" "tool_call" "tool_call_update"
                 "plan" "available_commands_update")
               (%update-tags client)))
    (ok (every (lambda (n) (equal sid (acp:session-id n))) (client-updates client)))
    (let ((tcu (fourth (client-update-objects client))))
      (ok (typep tcu 'acp:update-tool-call-update))
      (ok (typep (aref (acp:content tcu) 0) 'acp:diff))
      (ok (equal "old" (acp:old-text (aref (acp:content tcu) 0))))
      (ok (typep (aref (acp:content tcu) 1) 'acp:terminal)))))

(deftest loopback-updates-precede-the-prompt-response
  (multiple-value-bind (ra rc agent client sid) (session-of :script #'%work-script)
    (declare (ignore rc agent))
    (setf (gethash "/w/a.txt" (client-files client)) "old")
    (handler-bind ((acp:acp-permission-required #'acp:invoke-allow-once))
      (prompt ra sid "go"))
    (let* ((to-client (log-lines ra :to-client))
           (last-update (position "session/update" to-client :key #'line-method
                                                              :test #'equal :from-end t))
           (response (position-if (lambda (l)
                                    (let ((r (gethash "result" (json l))))
                                      (and (hash-table-p r) (gethash "stopReason" r))))
                                  to-client)))
      (ok (= 6 (count "session/update" to-client :key #'line-method :test #'equal)))
      (ok (and last-update response (< last-update response))))
    (ok (= 1 (count-method-lines ra "session/request_permission")))
    (ok (= 1 (count-method-lines ra "session/prompt")))))

;;; --- permission restarts ----------------------------------------------------------

(defun %ask-script (agent request)
  (multiple-value-bind (kind option)
      (acp:acp-ask-permission acp:*acp-remote* (acp:session-id request)
                              (tool-call-update "t9" :title "rm -rf build")
                              (options "allow_once" "allow_always" "reject_once" "reject_always"))
    (note agent :permission kind option))
  (%end))

(deftest-parametrize permission-restarts
    ((restart args kind option)
     ('acp:allow-once () :allow-once "allow_once")
     ('acp:allow-always () :allow-always "allow_always")
     ('acp:reject-once () :reject-once "reject_once")
     ('acp:reject-always () :reject-always "reject_always")
     ('acp:select-permission-option '("reject_always") :reject-always "reject_always")
     ('acp:cancel-permission () :cancelled nil))
  (multiple-value-bind (ra rc agent client sid) (session-of :script #'%ask-script)
    (declare (ignore rc client))
    (handler-bind ((acp:acp-permission-required
                     (lambda (c) (apply #'invoke-restart (find-restart restart c) args))))
      (prompt ra sid "go"))
    (ok (equal (list :permission kind option) (agent-event agent :permission)) (d restart))))

(deftest permission-unhandled-is-cancelled
  (multiple-value-bind (ra rc agent client sid) (session-of :script #'%ask-script)
    (declare (ignore rc client))
    (prompt ra sid "go")
    (ok (equal '(:permission :cancelled nil) (agent-event agent :permission)))))

(deftest permission-restarts-follow-the-options
  (let ((seen '()))
    (multiple-value-bind (ra rc agent client sid)
        (session-of :script (lambda (agent request)
                              (multiple-value-bind (kind)
                                  (acp:acp-ask-permission acp:*acp-remote* (acp:session-id request)
                                                          (tool-call-update "t2")
                                                          (options "allow_once" "reject_once"))
                                (note agent :permission kind))
                              (%end)))
      (declare (ignore rc client))
      (handler-bind ((acp:acp-permission-required
                       (lambda (c)
                         (setf seen (list (and (find-restart 'acp:allow-once c) t)
                                          (and (find-restart 'acp:allow-always c) t)
                                          (and (find-restart 'acp:reject-once c) t)
                                          (and (find-restart 'acp:reject-always c) t)
                                          (and (find-restart 'acp:cancel-permission c) t)))
                         (acp:invoke-reject-once c))))
        (prompt ra sid "go"))
      (ok (equal '(t nil t nil t) seen))
      (ok (equal '(:permission :reject-once) (agent-event agent :permission))))))

(deftest permission-unknown-option-id
  (multiple-value-bind (ra rc agent client sid) (session-of :script #'%ask-script)
    (declare (ignore rc agent client))
    (ok (signals
         (handler-bind ((acp:acp-permission-required
                          (lambda (c) (acp:invoke-select-permission-option "nope" c))))
           (prompt ra sid "go"))
         'acp:acp-error))))

(deftest permission-option-lists
  (multiple-value-bind (ra rc agent client sid)
      (session-of :script (lambda (agent request)
                            (multiple-value-bind (kind option)
                                (acp:acp-ask-permission acp:*acp-remote* (acp:session-id request)
                                                        (tool-call-update "t3")
                                                        '(("yes" "Yes" "allow_once")
                                                          ("never" "Never" "reject_always")))
                              (note agent :permission kind option))
                            (%end)))
    (declare (ignore rc client))
    (handler-bind ((acp:acp-permission-required #'acp:invoke-reject-always))
      (prompt ra sid "go"))
    (ok (equal '(:permission :reject-always "never") (agent-event agent :permission)))
    (let ((req (json (find "session/request_permission" (log-lines ra :to-client)
                           :key #'line-method :test #'equal))))
      (ok (equal "Yes" (gethash "name" (aref (gethash "options" (gethash "params" req)) 0)))))))

;;; --- cancellation -------------------------------------------------------------------

(deftest cancel-while-permission-pending
  (multiple-value-bind (ra rc agent client sid)
      (session-of :script (lambda (agent request)
                            (multiple-value-bind (kind)
                                (acp:acp-ask-permission acp:*acp-remote* (acp:session-id request)
                                                        (tool-call-update "t4")
                                                        (options "allow_once"))
                              (note agent :permission kind)
                              (%end (if (or (eq kind :cancelled)
                                            (member (acp:session-id request) (agent-cancelled agent)
                                                    :test #'equal))
                                        "cancelled" "end_turn")))))
    (declare (ignore rc client))
    (let ((res (handler-bind ((acp:acp-permission-required
                                (lambda (c)
                                  ;; the user presses stop while the dialog is open:
                                  ;; session/cancel goes out, then the dialog is answered
                                  (acp:acp-cancel ra (acp:make-acp 'acp:cancel-notification
                                                                   :session-id sid))
                                  (acp:invoke-allow-once c))))
                 (prompt ra sid "go"))))
      (ok (equal "cancelled" (acp:stop-reason res))))
    (ok (equal (list :cancel sid) (agent-event agent :cancel)))
    (ok (equal '(:permission :cancelled) (agent-event agent :permission))
        "a cancelled session's pending permission is answered cancelled")
    (ok (= 1 (count-method-lines ra "session/cancel")))))

(deftest cancel-is-per-session-and-per-request
  (multiple-value-bind (ra rc agent client sid) (session-of :script #'%ask-script)
    (declare (ignore rc client))
    ;; a cancel for another session, or sent before the request arrived, does not
    ;; override the answer
    (acp:acp-cancel ra (acp:make-acp 'acp:cancel-notification :session-id sid))
    (handler-bind ((acp:acp-permission-required
                     (lambda (c)
                       (acp:acp-cancel ra (acp:make-acp 'acp:cancel-notification
                                                        :session-id "other"))
                       (acp:invoke-allow-always c))))
      (prompt ra sid "go"))
    (ok (equal '(:permission :allow-always "allow_always") (agent-event agent :permission)))))

(deftest prompt-cancelled-condition-is-a-stop-reason
  (multiple-value-bind (ra rc agent client sid)
      (session-of :script (lambda (agent request)
                            (declare (ignore agent request))
                            (error 'acp:acp-request-cancelled)))
    (declare (ignore rc agent client))
    (let ((res (prompt ra sid "go")))
      (ok (typep res 'acp:prompt-response))
      (ok (equal "cancelled" (acp:stop-reason res))))))

(deftest cancel-request-notification
  (multiple-value-bind (ra rc agent) (session-of)
    (declare (ignore rc))
    (acp:acp-cancel-request ra (acp:make-acp 'acp:cancel-request-notification :request-id 12))
    (ok (equal '(:cancel-request 12) (agent-event agent :cancel-request)))))

;;; --- other session methods -------------------------------------------------------

(deftest set-mode-streams-the-mode-update
  (multiple-value-bind (ra rc agent client sid) (session-of)
    (declare (ignore rc agent))
    (ok (typep (acp:acp-set-session-mode ra (acp:make-acp 'acp:set-session-mode-request
                                                          :session-id sid :mode-id "code"))
               'acp:set-session-mode-response))
    (let ((u (first (client-update-objects client))))
      (ok (typep u 'acp:update-current-mode-update))
      (ok (equal "code" (acp:current-mode-id u))))))

(deftest load-session-replays-before-the-response
  (multiple-value-bind (ra rc agent client) (pair)
    (declare (ignore rc agent))
    (initialize ra)
    (ok (typep (acp:acp-load-session ra (acp:make-acp 'acp:load-session-request
                                                      :session-id "old" :cwd "/w" :mcp-servers #()))
               'acp:load-session-response))
    (ok (equal '("user_message_chunk" "agent_message_chunk") (%update-tags client)))
    ;; initialize's answer, the two replayed updates, then session/load's answer
    (let ((to-client (log-lines ra :to-client)))
      (ok (equal '(nil "session/update" "session/update" nil) (mapcar #'line-method to-client)))
      (ok (gethash "result" (json (car (last to-client))))))))

(deftest new-session-response-modes
  (multiple-value-bind (ra) (pair)
    (initialize ra)
    (let ((res (acp:acp-new-session ra (acp:make-acp 'acp:new-session-request
                                                     :cwd "/w" :mcp-servers #()))))
      (ok (typep res 'acp:new-session-response))
      (ok (equal "ask" (acp:current-mode-id (acp:modes res))))
      (ok (= 2 (length (acp:available-modes (acp:modes res))))))))

(deftest authenticate-and-auth-required
  (multiple-value-bind (ra) (pair)
    (initialize ra)
    (ok (typep (acp:acp-authenticate ra (acp:make-acp 'acp:authenticate-request
                                                      :method-id "agent-login"))
               'acp:authenticate-response))
    (ok (signals (acp:acp-authenticate ra (acp:make-acp 'acp:authenticate-request
                                                        :method-id "bad"))
                 'acp:acp-auth-required))))

(deftest elicitation-round-trip
  (multiple-value-bind (ra rc agent client sid)
      (session-of :script (lambda (agent request)
                            (let ((r (acp:acp-create-elicitation
                                      acp:*acp-remote*
                                      (acp:make-acp 'acp:create-elicitation-request
                                                    :message "Your name?" :mode "form"
                                                    :session-id (acp:session-id request)
                                                    :requested-schema (js "type" "object")))))
                              (note agent :elicited (acp:action r) (gethash "name" (acp:content r))))
                            (acp:acp-complete-elicitation
                             acp:*acp-remote*
                             (acp:make-acp 'acp:complete-elicitation-notification :elicitation-id "e1"))
                            (%end)))
    (declare (ignore rc))
    (prompt ra sid "go")
    (ok (equal '(:elicited "accept" "Ada") (agent-event agent :elicited)))
    (ok (equal '((:complete "e1") "Your name?") (client-elicitations client)))))

;;; --- capability gating --------------------------------------------------------------

(deftest unadvertised-client-capabilities-are-refused-locally
  (multiple-value-bind (ra rc agent client sid)
      (session-of :caps "{}"
                  :script (lambda (agent request)
                            (let ((sid (acp:session-id request)) (rc acp:*acp-remote*))
                              (handler-case
                                  (acp:acp-read-text-file
                                   rc (acp:make-acp 'acp:read-text-file-request :session-id sid :path "/a"))
                                (acp:acp-unsupported (c)
                                  (note agent :fs-refused (acp:acp-unsupported-feature c))))
                              (handler-case
                                  (acp:acp-create-terminal
                                   rc (acp:make-acp 'acp:create-terminal-request :session-id sid
                                                                                 :command "ls"))
                                (acp:acp-unsupported (c)
                                  (note agent :terminal-refused (acp:acp-unsupported-feature c))))
                              (handler-case
                                  (acp:acp-send-update
                                   rc sid (acp:make-acp 'acp:update-plan-removed :plan-id "p"))
                                (acp:acp-unsupported (c)
                                  (note agent :plan-refused (acp:acp-unsupported-feature c)))))
                            (%end)))
    (declare (ignore rc))
    (prompt ra sid "go")
    (ok (equal '(:fs-refused :read-text-file) (agent-event agent :fs-refused)))
    (ok (equal '(:terminal-refused :terminal) (agent-event agent :terminal-refused)))
    (ok (equal '(:plan-refused :plan-operations) (agent-event agent :plan-refused)))
    (ok (null (client-calls client)))
    (ok (null (client-updates client)))
    (ok (zerop (count-method-lines ra "fs/read_text_file")))
    (ok (zerop (count-method-lines ra "terminal/create")))))

(deftest plan-operations-with-the-capability
  (multiple-value-bind (ra rc agent client sid)
      (session-of :script (lambda (agent request)
                            (declare (ignore agent))
                            (acp:acp-send-update
                             acp:*acp-remote* (acp:session-id request)
                             (acp:make-acp 'acp:update-plan-update
                                           :plan (acp:make-acp 'acp:plan-markdown
                                                               :plan-id "p1" :content "# Plan")))
                            (%end)))
    (declare (ignore rc agent))
    (prompt ra sid "go")
    (ok (equal '("plan_update") (%update-tags client)))
    (ok (typep (acp:plan (first (client-update-objects client))) 'acp:plan-markdown))))

(deftest unadvertised-agent-capabilities-are-refused-locally
  (multiple-value-bind (ra rc agent) (pair :agent-caps "{}")
    (declare (ignore rc))
    (initialize ra)
    (let ((c (handler-case (acp:acp-load-session ra (acp:make-acp 'acp:load-session-request
                                                                  :session-id "s" :cwd "/w"
                                                                  :mcp-servers #()))
               (acp:acp-unsupported (c) c))))
      (ok (typep c 'acp:acp-unsupported))
      (ok (eq :load-session (acp:acp-unsupported-feature c)))
      (ok (equal "session/load" (acp:acp-error-method c))))
    (ok (signals (acp:acp-list-sessions ra (acp:make-acp 'acp:list-sessions-request))
                 'acp:acp-unsupported))
    (ok (zerop (count-method-lines ra "session/load")))
    (ok (null (agent-event agent :load)))))

;;; --- errors as conditions -----------------------------------------------------------

(deftest unknown-session-is-resource-not-found
  (multiple-value-bind (ra) (session-of)
    (let ((c (handler-case (prompt ra "sess-404" "hi") (acp:acp-error (c) c))))
      (ok (typep c 'acp:acp-resource-not-found))
      (ok (eql -32002 (acp:acp-error-code c)))
      (ok (equal "sess-404" (gethash "sessionId" (acp:acp-error-data c)))))
    (let ((line (json (car (last (log-lines ra :to-client))))))
      (ok (eql -32002 (gethash "code" (gethash "error" line)))))))

(deftest handler-errors-are-internal-errors
  (multiple-value-bind (ra rc agent client sid)
      (session-of :script (lambda (agent request)
                            (declare (ignore agent request))
                            (error "boom in the agent")))
    (declare (ignore rc agent client))
    (let ((c (handler-case (prompt ra sid "go") (acp:acp-error (c) c))))
      (ok (typep c 'acp:acp-internal-error))
      (ok (search "boom in the agent" (acp:acp-error-message c))))))

(deftest unimplemented-methods-are-method-not-found
  (multiple-value-bind (ra) (pair :agent-caps "{\"sessionCapabilities\":{\"list\":{}}}")
    (initialize ra)
    (let ((c (handler-case (acp:acp-list-sessions ra (acp:make-acp 'acp:list-sessions-request))
               (acp:acp-error (c) c))))
      (ok (typep c 'acp:acp-method-not-found))
      (ng (typep c 'acp:acp-unsupported))
      (ok (eql -32601 (acp:acp-error-code c))))))

(deftest invalid-params-from-the-peer
  (multiple-value-bind (ra rc agent client sid) (session-of)
    (declare (ignore rc agent client))
    (ok (signals (acp:remote-call ra "session/prompt" (js "sessionId" sid "prompt" "text"))
                 'acp:acp-invalid-params))))

(deftest cancelled-error-from-other-methods
  (multiple-value-bind (ra rc agent client sid) (session-of :failures 1)
    (declare (ignore rc agent client))
    (let ((c (handler-case (acp:acp-set-session-mode
                            ra (acp:make-acp 'acp:set-session-mode-request
                                             :session-id sid :mode-id "code"))
               (acp:acp-error (c) c))))
      (ok (typep c 'acp:acp-request-cancelled))
      (ok (eql -32800 (acp:acp-error-code c))))))

(deftest remote-call-restarts
  (multiple-value-bind (ra rc agent client sid) (session-of :failures 2)
    (declare (ignore rc client))
    ;; RETRY sends again: two cancelled answers, then success
    (let ((tries 0))
      (ok (typep (handler-bind ((acp:acp-request-cancelled
                                  (lambda (c) (incf tries) (acp:invoke-retry c))))
                   (acp:acp-set-session-mode ra (acp:make-acp 'acp:set-session-mode-request
                                                              :session-id sid :mode-id "code")))
                 'acp:set-session-mode-response))
      (ok (= 2 tries)))
    (ok (zerop (agent-failures agent)))
    ;; USE-VALUE returns the given object instead
    (let ((fallback (%end "refusal")))
      (ok (eq fallback
              (handler-bind ((acp:acp-resource-not-found
                               (lambda (c) (acp:invoke-use-value fallback c))))
                (prompt ra "sess-404" "hi")))))))

;;; --- extensions over the pair ---------------------------------------------------

(deftest extension-calls
  (multiple-value-bind (ra rc agent) (session-of)
    (declare (ignore rc))
    (ok (eql 5 (gethash "n" (gethash "echo" (acp:acp-call-ext ra "_cl-stack.test/echo" (js "n" 5))))))
    (ok (signals (acp:acp-call-ext ra "_com.example/missing" (js)) 'acp:acp-method-not-found))
    (ok (signals (acp:acp-call-ext ra "session/new" (js)) 'acp:acp-invalid-request))
    (ok (eq t (acp:acp-notify-ext ra "_cl-stack.test/ping" (js "at" 1))))
    (ok (equal "_cl-stack.test/ping" (second (agent-event agent :ext-notification))))
    (ok (signals (acp:acp-notify-ext ra "ping" (js)) 'acp:acp-invalid-request))))
