(in-package #:acp-protocol/tests)

;;; The message model: the method table against the vendored meta.json, a
;;; decode → encode round trip of every JSON-RPC example of the v1 docs
;;; (tests/fixtures/v1, Apache-2.0, see VENDOR.md) and of the typed
;;; fragments, construction from Lisp, and the envelope rules.

(defun payload (msg)
  (ecase (acp:acp-message-kind msg)
    ((:request :notification)
     (let ((p (acp:acp-message-params msg)))
       (if (typep p 'acp:session-notification) (acp:update p) p)))
    (:response (acp:acp-message-result msg))
    (:error (acp:acp-message-error msg))))

;;; --- constants and the method table (given code) --------------------------------

(deftest protocol-constants
  (ok (eql 1 acp:+acp-protocol-version+))
  (ok (equal "1.34.1" acp:+acp-schema-version+))
  (ok (equal "_" acp:+acp-extension-prefix+))
  (ok (acp:acp-extension-method-p "_com.example/x"))
  (ng (acp:acp-extension-method-p "session/new"))
  (ng (acp:acp-extension-method-p "")))

(deftest method-table-matches-meta-json
  (let* ((meta (fixture-json "meta.json"))
         (names (append (loop for v being the hash-values of (gethash "agentMethods" meta) collect v)
                        (loop for v being the hash-values of (gethash "clientMethods" meta) collect v)
                        (loop for v being the hash-values of (gethash "protocolMethods" meta)
                              collect v))))
    (ok (eql 1 (gethash "version" meta)))
    (ok (= (length names) (length acp:+acp-methods+)))
    (dolist (name names)
      (ok (acp:acp-method-row name) name))
    (loop for v being the hash-values of (gethash "agentMethods" meta)
          do (ok (eq :agent (acp:acp-method-direction v)) v))
    (loop for v being the hash-values of (gethash "clientMethods" meta)
          do (ok (eq :client (acp:acp-method-direction v)) v))))

(deftest method-table-rows-are-defined
  (dolist (row acp:+acp-methods+)
    (destructuring-bind (method dir kind req res gf cap) row
      (ok (member dir '(:agent :client :both)) method)
      (ok (find-class req nil) method)
      (if (eq kind :request)
          (ok (find-class res nil) method)
          (ok (null res) method))
      (ok (fboundp gf) method)
      (ok (or (null cap) (member cap acp:+acp-client-features+)
              (member cap acp:+acp-agent-features+))
          method))))

;;; --- fixture round trips ------------------------------------------------------------

(deftest-parametrize fixture-round-trip
    ((file kind method class)
     ("agent-plan-01.json" :notification "session/update" 'acp:update-plan)
     ("agent-plan-02.json" :notification "session/update" 'acp:update-plan-update)
     ("agent-plan-03.json" :notification "session/update" 'acp:update-plan-update)
     ("agent-plan-04.json" :notification "session/update" 'acp:update-plan-removed)
     ("authentication-01.json" :response "initialize" 'acp:initialize-response)
     ("authentication-02.json" :request "initialize" 'acp:initialize-request)
     ("authentication-03.json" :request "authenticate" 'acp:authenticate-request)
     ("authentication-04.json" :response "authenticate" 'acp:authenticate-response)
     ("authentication-05.json" :request "logout" 'acp:logout-request)
     ("authentication-06.json" :response "logout" 'acp:logout-response)
     ("elicitation-01.json" :request "elicitation/create" 'acp:create-elicitation-request)
     ("elicitation-02.json" :request "elicitation/create" 'acp:create-elicitation-request)
     ("error-01.json" :error "session/prompt" 'acp:acp-error-object)
     ("extensibility-01.json" :request "session/prompt" 'acp:prompt-request)
     ("extensibility-02.json" :request "_com.example/workspace/buffers" 'hash-table)
     ("extensibility-03.json" :response "_com.example/workspace/buffers" 'hash-table)
     ("extensibility-04.json" :error "_com.example/workspace/buffers" 'acp:acp-error-object)
     ("extensibility-05.json" :notification "_com.example/file_opened" 'hash-table)
     ("extensibility-06.json" :response "initialize" 'acp:initialize-response)
     ("file-system-01.json" :request "initialize" 'acp:initialize-request)
     ("file-system-02.json" :request "fs/read_text_file" 'acp:read-text-file-request)
     ("file-system-03.json" :response "fs/read_text_file" 'acp:read-text-file-response)
     ("file-system-04.json" :request "fs/write_text_file" 'acp:write-text-file-request)
     ("file-system-05.json" :response "fs/write_text_file" 'acp:write-text-file-response)
     ("initialization-01.json" :request "initialize" 'acp:initialize-request)
     ("initialization-02.json" :response "initialize" 'acp:initialize-response)
     ("prompt-turn-01.json" :notification "session/update" 'acp:update-session-message)
     ("prompt-turn-02.json" :notification "session/update" 'acp:update-session-message-chunk)
     ("prompt-turn-03.json" :request "session/prompt" 'acp:prompt-request)
     ("prompt-turn-04.json" :notification "session/update" 'acp:update-plan)
     ("prompt-turn-05.json" :notification "session/update" 'acp:update-agent-message-chunk)
     ("prompt-turn-06.json" :notification "session/update" 'acp:update-tool-call)
     ("prompt-turn-07.json" :notification "session/update" 'acp:update-notice)
     ("prompt-turn-08.json" :notification "session/update" 'acp:update-compaction-update)
     ("prompt-turn-09.json" :notification "session/update" 'acp:update-compaction-summary-chunk)
     ("prompt-turn-10.json" :notification "session/update" 'acp:update-compaction-update)
     ("prompt-turn-11.json" :notification "session/update" 'acp:update-usage-update)
     ("prompt-turn-12.json" :response "session/prompt" 'acp:prompt-response)
     ("prompt-turn-13.json" :notification "session/update" 'acp:update-tool-call-update)
     ("prompt-turn-14.json" :notification "session/update" 'acp:update-tool-call-update)
     ("prompt-turn-15.json" :notification "session/cancel" 'acp:cancel-notification)
     ("session-config-options-01.json" :response "session/new" 'acp:new-session-response)
     ("session-config-options-02.json" :request "session/set_config_option" 'acp:set-session-config-option-request)
     ("session-config-options-03.json" :request "session/set_config_option" 'acp:set-session-config-option-request)
     ("session-config-options-04.json" :response "session/set_config_option" 'acp:set-session-config-option-response)
     ("session-config-options-05.json" :notification "session/update" 'acp:update-config-option-update)
     ("session-delete-01.json" :response "initialize" 'acp:initialize-response)
     ("session-delete-02.json" :request "session/delete" 'acp:delete-session-request)
     ("session-delete-03.json" :response "session/delete" 'acp:delete-session-response)
     ("session-list-01.json" :response "initialize" 'acp:initialize-response)
     ("session-list-02.json" :request "session/list" 'acp:list-sessions-request)
     ("session-list-03.json" :response "session/list" 'acp:list-sessions-response)
     ("session-list-04.json" :notification "session/update" 'acp:update-session-info-update)
     ("session-modes-01.json" :response "session/new" 'acp:new-session-response)
     ("session-modes-02.json" :request "session/set_mode" 'acp:set-session-mode-request)
     ("session-modes-03.json" :notification "session/update" 'acp:update-current-mode-update)
     ("session-modes-04.json" :request "session/request_permission" 'acp:request-permission-request)
     ("session-setup-01.json" :request "session/new" 'acp:new-session-request)
     ("session-setup-02.json" :response "session/new" 'acp:new-session-response)
     ("session-setup-03.json" :response "initialize" 'acp:initialize-response)
     ("session-setup-04.json" :request "session/load" 'acp:load-session-request)
     ("session-setup-05.json" :notification "session/update" 'acp:update-user-message-chunk)
     ("session-setup-06.json" :notification "session/update" 'acp:update-agent-message-chunk)
     ("session-setup-07.json" :response "session/load" 'acp:load-session-response)
     ("session-setup-08.json" :response "initialize" 'acp:initialize-response)
     ("session-setup-09.json" :request "session/resume" 'acp:resume-session-request)
     ("session-setup-10.json" :response "session/resume" 'acp:resume-session-response)
     ("session-setup-11.json" :response "initialize" 'acp:initialize-response)
     ("session-setup-12.json" :request "session/close" 'acp:close-session-request)
     ("session-setup-13.json" :response "session/close" 'acp:close-session-response)
     ("session-setup-14.json" :request "session/load" 'acp:load-session-request)
     ("session-setup-15.json" :request "session/new" 'acp:new-session-request)
     ("session-setup-16.json" :response "initialize" 'acp:initialize-response)
     ("session-setup-17.json" :response "initialize" 'acp:initialize-response)
     ("slash-commands-01.json" :notification "session/update" 'acp:update-available-commands-update)
     ("slash-commands-02.json" :request "session/prompt" 'acp:prompt-request)
     ("subagents-01.json" :request "initialize" 'acp:initialize-request)
     ("subagents-02.json" :notification "session/update" 'acp:update-subagent-update)
     ("subagents-03.json" :notification "session/update" 'acp:update-tool-call)
     ("subagents-04.json" :request "session/request_permission" 'acp:request-permission-request)
     ("subagents-05.json" :notification "session/update" 'acp:update-subagent-update)
     ("subagents-06.json" :notification "session/update" 'acp:update-session-message)
     ("subagents-07.json" :notification "session/update" 'acp:update-subagent-update)
     ("subagents-08.json" :notification "session/update" 'acp:update-subagent-update)
     ("subagents-09.json" :notification "session/cancel" 'acp:cancel-notification)
     ("terminals-01.json" :request "initialize" 'acp:initialize-request)
     ("terminals-02.json" :request "terminal/create" 'acp:create-terminal-request)
     ("terminals-03.json" :response "terminal/create" 'acp:create-terminal-response)
     ("terminals-04.json" :notification "session/update" 'acp:update-tool-call)
     ("terminals-05.json" :request "terminal/output" 'acp:terminal-output-request)
     ("terminals-06.json" :response "terminal/output" 'acp:terminal-output-response)
     ("terminals-07.json" :request "terminal/wait_for_exit" 'acp:wait-for-terminal-exit-request)
     ("terminals-08.json" :response "terminal/wait_for_exit" 'acp:wait-for-terminal-exit-response)
     ("terminals-09.json" :request "terminal/kill" 'acp:kill-terminal-request)
     ("terminals-10.json" :request "terminal/release" 'acp:release-terminal-request)
     ("tool-calls-01.json" :notification "session/update" 'acp:update-tool-call)
     ("tool-calls-02.json" :notification "session/update" 'acp:update-tool-call-update)
     ("tool-calls-03.json" :request "session/request_permission" 'acp:request-permission-request)
     ("tool-calls-04.json" :response "session/request_permission" 'acp:request-permission-response)
     ("tool-calls-05.json" :response "session/request_permission" 'acp:request-permission-response)
     )
  (let* ((text (fixture-text file))
         (msg (acp:decode-acp-message text :method method)))
    (ok (eq kind (acp:acp-message-kind msg)) file)
    (ok (typep (payload msg) class) file)
    (ok (eq (not (eq class 'hash-table)) (and (acp:acp-message-known-p msg) t)) file)
    (ok (same-json-text-p text (acp:encode-acp-message msg)) file)))

(deftest-parametrize fragment-round-trip
    ((file parse-as class)
     ("fragment-content-01.json" 'acp:content-block 'acp:text-content)
     ("fragment-content-02.json" 'acp:content-block 'acp:image-content)
     ("fragment-content-03.json" 'acp:content-block 'acp:audio-content)
     ("fragment-content-04.json" 'acp:content-block 'acp:embedded-resource)
     ("fragment-content-05.json" 'acp:content-block 'acp:resource-link)
     ("fragment-tool-calls-01.json" 'acp:tool-call-content 'acp:content)
     ("fragment-tool-calls-02.json" 'acp:tool-call-content 'acp:diff)
     ("fragment-tool-calls-03.json" 'acp:tool-call-content 'acp:terminal)
     ("fragment-tool-calls-04.json" 'acp:tool-call-content 'acp:session-reference)
     ("fragment-tool-calls-05.json" 'acp:tool-call-location 'acp:tool-call-location)
     ("fragment-session-setup-01.json" 'acp:mcp-server-stdio 'acp:mcp-server-stdio)
     ("fragment-session-setup-02.json" 'acp:mcp-server-http 'acp:mcp-server-http)
     ("fragment-session-setup-03.json" 'acp:mcp-server-sse 'acp:mcp-server-sse)
     ("fragment-session-config-options-01.json" 'acp:session-config-option
      'acp:session-config-option)
     ("fragment-authentication-01.json" 'acp:auth-method-agent 'acp:auth-method-agent)
     ("fragment-authentication-02.json" 'acp:auth-method-terminal 'acp:auth-method-terminal))
  (let* ((table (fixture-json file))
         (object (acp:parse-acp-object parse-as table)))
    (ok (typep object class) file)
    (ok (json-equal table (acp:acp-object-table object)) file)
    (ok (same-json-text-p (fixture-text file) (acp:encode-acp-object object)) file)))

;;; --- typed fields of decoded examples ---------------------------------------------

(deftest decoded-initialize-fields
  (let* ((req (acp:acp-message-params (acp:decode-acp-message (fixture-text "initialization-01.json"))))
         (caps (acp:client-capabilities req)))
    (ok (typep req 'acp:initialize-request))
    (ok (eql 1 (acp:protocol-version req)))
    (ok (eq t (acp:read-text-file (acp:fs caps))))
    (ok (eq t (acp:terminal caps)))
    (ok (equal "my-client" (acp:name (acp:client-info req)))))
  (let ((res (acp:acp-message-result
              (acp:decode-acp-message (fixture-text "initialization-02.json") :method "initialize"))))
    (ok (typep res 'acp:initialize-response))
    (ok (eq t (acp:load-session (acp:agent-capabilities res))))
    (ok (eq t (acp:image (acp:prompt-capabilities (acp:agent-capabilities res)))))
    (ok (equalp #() (acp:auth-methods res)))))

(deftest decoded-prompt-and-updates
  (let ((req (acp:acp-message-params (acp:decode-acp-message (fixture-text "prompt-turn-03.json")))))
    (ok (typep req 'acp:prompt-request))
    (ok (every (lambda (b) (typep b 'acp:content-block)) (acp:prompt req))))
  (let ((n (acp:acp-message-params (acp:decode-acp-message (fixture-text "tool-calls-01.json")))))
    (ok (typep n 'acp:session-notification))
    (ok (typep (acp:update n) 'acp:update-tool-call))
    (ok (typep (acp:update n) 'acp:tool-call))
    (ok (stringp (acp:tool-call-id (acp:update n))))
    (ok (equal "tool_call" (acp:session-update (acp:update n)))))
  (let ((res (acp:acp-message-result
              (acp:decode-acp-message (fixture-text "prompt-turn-12.json") :method "session/prompt"))))
    (ok (typep res 'acp:prompt-response))
    (ok (member (acp:stop-reason res) acp:+acp-stop-reasons+ :test #'equal))))

(deftest decoded-permission-request-and-outcomes
  (let ((req (acp:acp-message-params (acp:decode-acp-message (fixture-text "tool-calls-03.json")))))
    (ok (typep req 'acp:request-permission-request))
    (ok (typep (acp:tool-call req) 'acp:tool-call-update))
    (ng (typep (acp:tool-call req) 'acp:session-update))
    (ok (every (lambda (o) (member (acp:kind o) acp:+acp-permission-option-kinds+ :test #'equal))
               (acp:options req))))
  (let ((sel (acp:acp-message-result
              (acp:decode-acp-message (fixture-text "tool-calls-04.json")
                                      :method "session/request_permission")))
        (can (acp:acp-message-result
              (acp:decode-acp-message (fixture-text "tool-calls-05.json")
                                      :method "session/request_permission"))))
    (ok (typep (acp:outcome sel) '(or acp:selected-permission-outcome acp:cancelled-permission-outcome)))
    (ok (typep (acp:outcome can) '(or acp:selected-permission-outcome acp:cancelled-permission-outcome)))
    (ng (eq (type-of (acp:outcome sel)) (type-of (acp:outcome can))))))

(deftest decoded-error-and-extension-messages
  (let ((e (acp:decode-acp-message (fixture-text "error-01.json") :method "session/prompt")))
    (ok (eq :error (acp:acp-message-kind e)))
    (ok (eql 3 (acp:acp-message-id e)))
    (ok (eql -32002 (acp:code (acp:acp-message-error e))))
    (ok (equal "sess_abc123def456" (gethash "sessionId" (acp:data (acp:acp-message-error e))))))
  (let ((r (acp:decode-acp-message (fixture-text "extensibility-02.json"))))
    (ok (eq :request (acp:acp-message-kind r)))
    (ok (equal "_com.example/workspace/buffers" (acp:acp-message-method r)))
    (ng (acp:acp-message-known-p r))
    (ok (hash-table-p (acp:acp-message-params r))))
  (let ((n (acp:decode-acp-message (fixture-text "extensibility-05.json"))))
    (ok (eq :notification (acp:acp-message-kind n)))
    (ok (null (acp:acp-message-id n)))))

;;; --- construction from Lisp -------------------------------------------------------

(deftest build-agent-thought-chunk
  (let ((n (acp:make-acp 'acp:session-notification
                         :session-id "s1"
                         :update (acp:make-acp 'acp:update-agent-thought-chunk
                                               :content (acp:make-acp 'acp:text-content
                                                                      :text "thinking")))))
    (ok (object-json-p n "{\"sessionId\":\"s1\",\"update\":{\"sessionUpdate\":\"agent_thought_chunk\",
                          \"content\":{\"type\":\"text\",\"text\":\"thinking\"}}}"))
    (ok (typep (acp:update (acp:parse-acp-object 'acp:session-notification (acp:acp-object-table n)))
               'acp:update-agent-thought-chunk))))

(deftest build-every-update-tag
  (dolist (pair '((acp:update-user-message-chunk . "user_message_chunk")
                  (acp:update-agent-message-chunk . "agent_message_chunk")
                  (acp:update-agent-thought-chunk . "agent_thought_chunk")
                  (acp:update-tool-call . "tool_call")
                  (acp:update-tool-call-update . "tool_call_update")
                  (acp:update-plan . "plan")
                  (acp:update-plan-update . "plan_update")
                  (acp:update-plan-removed . "plan_removed")
                  (acp:update-available-commands-update . "available_commands_update")
                  (acp:update-current-mode-update . "current_mode_update")
                  (acp:update-config-option-update . "config_option_update")
                  (acp:update-session-info-update . "session_info_update")
                  (acp:update-usage-update . "usage_update")
                  (acp:update-notice . "notice")
                  (acp:update-compaction-update . "compaction_update")
                  (acp:update-compaction-summary-chunk . "compaction_summary_chunk")
                  (acp:update-subagent-update . "subagent_update")
                  (acp:update-session-message . "session_message")
                  (acp:update-session-message-chunk . "session_message_chunk")))
    (ok (equal (cdr pair) (acp:session-update (make-instance (car pair)))) (cdr pair))))

(deftest build-protocol-notifications
  (ok (object-json-p (acp:make-acp 'acp:cancel-request-notification :request-id 7)
                     "{\"requestId\":7}"))
  (ok (object-json-p (acp:make-acp 'acp:cancel-request-notification :request-id "r-1")
                     "{\"requestId\":\"r-1\"}"))
  (ok (object-json-p (acp:make-acp 'acp:complete-elicitation-notification :elicitation-id "e1")
                     "{\"elicitationId\":\"e1\"}"))
  (ok (object-json-p (acp:make-acp 'acp:cancel-notification :session-id "s1")
                     "{\"sessionId\":\"s1\"}")))

(deftest build-permission-outcomes
  (ok (object-json-p (acp:make-acp 'acp:request-permission-response
                                   :outcome (acp:make-acp 'acp:selected-permission-outcome
                                                          :option-id "allow"))
                     "{\"outcome\":{\"outcome\":\"selected\",\"optionId\":\"allow\"}}"))
  (ok (object-json-p (acp:make-acp 'acp:request-permission-response
                                   :outcome (make-instance 'acp:cancelled-permission-outcome))
                     "{\"outcome\":{\"outcome\":\"cancelled\"}}")))

(deftest build-meta-and-null
  (let ((r (acp:make-acp 'acp:prompt-response :stop-reason "end_turn"
                                              :meta (js "traceparent" "00-abc-01"))))
    (ok (object-json-p r "{\"stopReason\":\"end_turn\",\"_meta\":{\"traceparent\":\"00-abc-01\"}}")))
  (let ((d (acp:make-acp 'acp:diff :path "/a" :old-text :null :new-text "x")))
    (ok (object-json-p d "{\"type\":\"diff\",\"path\":\"/a\",\"oldText\":null,\"newText\":\"x\"}"))))

(deftest build-false-booleans
  (let ((caps (make-instance 'acp:file-system-capabilities :read-text-file t :write-text-file nil)))
    (ok (object-json-p caps "{\"readTextFile\":true,\"writeTextFile\":false}"))))

;;; --- envelope rules ---------------------------------------------------------------

(deftest encode-envelopes
  (ok (same-json-text-p
       (acp:encode-acp-message
        (acp:make-acp-request "session/cancel-me" (js "a" 1) :id 9))
       "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"session/cancel-me\",\"params\":{\"a\":1}}"))
  (ok (same-json-text-p
       (acp:encode-acp-message
        (acp:make-acp-notification "session/cancel"
                                   (acp:make-acp 'acp:cancel-notification :session-id "s")))
       "{\"jsonrpc\":\"2.0\",\"method\":\"session/cancel\",\"params\":{\"sessionId\":\"s\"}}"))
  (ok (same-json-text-p
       (acp:encode-acp-message
        (acp:make-acp-response (acp:make-acp 'acp:prompt-response :stop-reason "refusal") :id 4))
       "{\"jsonrpc\":\"2.0\",\"id\":4,\"result\":{\"stopReason\":\"refusal\"}}"))
  (ok (same-json-text-p
       (acp:encode-acp-message (acp:make-acp-error-response -32002 "Resource not found"
                                                            :id 5 :data (js "sessionId" "s")))
       "{\"jsonrpc\":\"2.0\",\"id\":5,\"error\":{\"code\":-32002,\"message\":\"Resource not found\",
         \"data\":{\"sessionId\":\"s\"}}}")))

(deftest decode-response-without-method-stays-raw
  (let ((m (acp:decode-acp-message (fixture-text "prompt-turn-12.json"))))
    (ok (eq :response (acp:acp-message-kind m)))
    (ok (hash-table-p (acp:acp-message-result m)))
    (ng (acp:acp-message-known-p m))))

(deftest decode-absent-params
  (let ((m (acp:decode-acp-message "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"logout\"}")))
    (ok (typep (acp:acp-message-params m) 'acp:logout-request))))

(deftest decode-bad-envelopes
  (ok (signals (acp:decode-acp-message "{not json") 'acp:acp-invalid-request))
  (ok (signals (acp:decode-acp-message "[1,2]") 'acp:acp-invalid-request))
  (ok (signals (acp:decode-acp-message "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"logout\"}")
               'acp:acp-invalid-request)))

(deftest decode-bad-params
  (let ((c (handler-case
               (acp:decode-acp-message
                "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"session/prompt\",
                  \"params\":{\"sessionId\":\"s\",\"prompt\":\"not an array\"}}")
             (acp:acp-invalid-params (c) c))))
    (ok (typep c 'acp:acp-invalid-params))
    (ok (eql -32602 (acp:acp-error-code c)))
    (ok (vectorp (gethash "issues" (acp:acp-error-data c))))
    (ok (plusp (length (gethash "issues" (acp:acp-error-data c)))))))

(deftest parse-acp-object-sources
  (ok (typep (acp:parse-acp-object 'acp:cancel-notification "{\"sessionId\":\"s\"}")
             'acp:cancel-notification))
  (ok (signals (acp:parse-acp-object 'acp:cancel-notification "[1]") 'acp:acp-invalid-params))
  (ok (signals (acp:parse-acp-object 'acp:cancel-notification "{nope") 'acp:acp-invalid-params))
  (ok (signals (acp:parse-acp-object 'acp:cancel-notification (js)) 'acp:acp-invalid-params))
  (let ((h (js "sessionId" "s")))
    (ok (eq h (acp:acp-object-table h)))))
