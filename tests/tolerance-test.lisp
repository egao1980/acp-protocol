(in-package #:acp-protocol/tests)

;;; Unknown fields, kinds, values and methods are tolerated, never errors:
;;; they are kept and re-emitted (model) or ignored (connection).

(defun round-trips-p (text &key method)
  (same-json-text-p text (acp:encode-acp-message (acp:decode-acp-message text :method method))))

(deftest unknown-root-and-nested-fields-are-kept
  (let* ((text "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\",\"params\":{
                 \"protocolVersion\":1,\"futureRoot\":{\"x\":[1,2]},
                 \"clientCapabilities\":{\"fs\":{\"readTextFile\":true,\"futureFlag\":true},
                                         \"futureCapability\":{}},
                 \"clientInfo\":{\"name\":\"c\",\"version\":\"1\",\"vendor\":\"v\"}}}")
         (req (acp:acp-message-params (acp:decode-acp-message text))))
    (ok (typep req 'acp:initialize-request))
    (ok (eq t (acp:read-text-file (acp:fs (acp:client-capabilities req)))))
    (ok (json-equal (js "x" #(1 2)) (gethash "futureRoot" (stack-schema:schema-extras req))))
    (ok (round-trips-p text))))

(deftest unknown-session-update-kind
  (let* ((text "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"s\",
                 \"update\":{\"sessionUpdate\":\"hologram_update\",\"beam\":{\"power\":9}}}}")
         (n (acp:acp-message-params (acp:decode-acp-message text))))
    (ok (typep (acp:update n) 'acp:unknown-session-update))
    (ok (equal "hologram_update" (acp:session-update (acp:update n))))
    (ok (round-trips-p text))))

(deftest known-update-kinds-never-fall-back
  (let ((n (acp:acp-message-params (acp:decode-acp-message (fixture-text "agent-plan-01.json")))))
    (ng (typep (acp:update n) 'acp:unknown-session-update))))

(deftest unknown-content-block-type
  (let* ((text "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/prompt\",\"params\":{
                 \"sessionId\":\"s\",\"prompt\":[{\"type\":\"text\",\"text\":\"hi\"},
                 {\"type\":\"video\",\"uri\":\"file:///a.mp4\",\"frames\":30}]}}")
         (req (acp:acp-message-params (acp:decode-acp-message text))))
    (ok (typep (aref (acp:prompt req) 0) 'acp:text-content))
    (ok (typep (aref (acp:prompt req) 1) 'acp:unknown-content-block))
    (ok (equal "video" (acp:wire-type (aref (acp:prompt req) 1))))
    (ok (round-trips-p text))))

(deftest unknown-tool-call-content-and-plan-content
  (let ((text "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"s\",
                \"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"t1\",\"title\":\"x\",
                \"content\":[{\"type\":\"chart\",\"series\":[1]}]}}}"))
    (ok (typep (aref (acp:content (acp:update (acp:acp-message-params
                                               (acp:decode-acp-message text))))
                     0)
               'acp:unknown-tool-call-content))
    (ok (round-trips-p text)))
  (let ((text "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"s\",
                \"update\":{\"sessionUpdate\":\"plan_update\",
                \"plan\":{\"type\":\"kanban\",\"planId\":\"p\",\"columns\":[]}}}}"))
    (ok (typep (acp:plan (acp:update (acp:acp-message-params (acp:decode-acp-message text))))
               'acp:unknown-plan-update-content))
    (ok (round-trips-p text))))

(deftest-parametrize unknown-enum-values-are-kept
    ((text accessor expected)
     ("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"stopReason\":\"paused\"}}"
      'acp:stop-reason "paused")
     ("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"s\",
        \"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"t\",\"title\":\"x\",
        \"kind\":\"teleport\",\"status\":\"queued\"}}}"
      'acp:kind "teleport")
     ("{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"s\",
        \"update\":{\"sessionUpdate\":\"notice\",\"severity\":\"_vendor_debug\",\"title\":\"n\"}}}"
      'acp:severity "_vendor_debug"))
  (let* ((m (acp:decode-acp-message text :method "session/prompt"))
         (o (or (acp:acp-message-result m) (acp:update (acp:acp-message-params m)))))
    (ok (equal expected (funcall accessor o)))
    (ok (round-trips-p text :method "session/prompt"))))

(deftest unknown-capabilities-and-meta
  (let ((caps (client-caps "{\"terminal\":true,\"holodeck\":{\"rooms\":3},
                             \"_meta\":{\"io.github.egao1980/units\":true}}")))
    (ok (eq t (acp:terminal caps)))
    (ok (acp:client-supports-p caps :terminal))
    (multiple-value-bind (v found) (acp:capability-meta caps "io.github.egao1980/units")
      (ok (eq t v))
      (ok found))
    (multiple-value-bind (v found) (acp:capability-meta caps "com.example/other")
      (ok (null v))
      (ng found))))

;;; --- at the connection -----------------------------------------------------------

(defun agent-connection (rc)
  "The agent side's connection of a loopback pair (REMOTE-CLIENT's)."
  (acp:remote-connection rc))

(deftest unknown-notification-is-ignored
  (multiple-value-bind (ra rc agent) (pair)
    (initialize ra)
    (let ((conn (agent-connection rc)))
      (ok (null (acp:acp-handle-message
                 conn "{\"jsonrpc\":\"2.0\",\"method\":\"session/hologram\",\"params\":{}}")))
      (ok (null (acp:acp-handle-message
                 conn "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{}}")))
      (ok (null (agent-event agent :ext-notification))))))

(deftest unknown-request-is-method-not-found
  (multiple-value-bind (ra rc) (pair)
    (initialize ra)
    (let ((answer (json (acp:acp-handle-message
                         (agent-connection rc)
                         "{\"jsonrpc\":\"2.0\",\"id\":41,\"method\":\"session/hologram\",\"params\":{}}"))))
      (ok (eql 41 (gethash "id" answer)))
      (ok (eql -32601 (gethash "code" (gethash "error" answer)))))
    ;; a client-side method sent to the agent is not the agent's to answer
    (let ((answer (json (acp:acp-handle-message
                         (agent-connection rc)
                         "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"fs/read_text_file\",
                           \"params\":{\"sessionId\":\"s\",\"path\":\"/a\"}}"))))
      (ok (eql -32601 (gethash "code" (gethash "error" answer)))))))

(deftest extension-notifications-and-requests
  (multiple-value-bind (ra rc agent) (pair)
    (initialize ra)
    (let ((conn (agent-connection rc)))
      (ok (null (acp:acp-handle-message
                 conn "{\"jsonrpc\":\"2.0\",\"method\":\"_com.example/file_opened\",
                        \"params\":{\"path\":\"/a\"}}")))
      (let ((e (agent-event agent :ext-notification)))
        (ok (equal "_com.example/file_opened" (second e)))
        (ok (equal "/a" (gethash "path" (third e)))))
      (let ((answer (json (acp:acp-handle-message
                           conn "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"_cl-stack.test/echo\",
                                  \"params\":{\"n\":1}}"))))
        (ok (eql 1 (gethash "n" (gethash "echo" (gethash "result" answer))))))
      (let ((answer (json (acp:acp-handle-message
                           conn "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"_com.example/nope\",
                                  \"params\":{}}"))))
        (ok (eql -32601 (gethash "code" (gethash "error" answer))))))))

(deftest unknown-fields-in-a-live-request
  (multiple-value-bind (ra rc agent) (pair)
    (initialize ra)
    (let ((answer (json (acp:acp-handle-message
                         (agent-connection rc)
                         "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"session/new\",
                           \"params\":{\"cwd\":\"/w\",\"mcpServers\":[],\"futureOption\":true,
                                      \"_meta\":{\"traceparent\":\"00-x-01\"}}}"))))
      (ok (stringp (gethash "sessionId" (gethash "result" answer))))
      (ok (equal "/w" (second (agent-event agent :new-session)))))))

(deftest bad-lines-get-json-rpc-errors
  (multiple-value-bind (ra rc) (pair)
    (initialize ra)
    (let ((conn (agent-connection rc)))
      (let ((a (json (acp:acp-handle-message conn "{not json"))))
        (ok (eql -32700 (gethash "code" (gethash "error" a))))
        (ok (eq :null (gethash "id" a))))
      (let ((a (json (acp:acp-handle-message conn "42"))))
        (ok (eql -32600 (gethash "code" (gethash "error" a))))
        (ok (eq :null (gethash "id" a))))
      (let ((a (json (acp:acp-handle-message
                      conn "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"session/prompt\",
                             \"params\":{\"sessionId\":\"s\"}}"))))
        (ok (eql -32602 (gethash "code" (gethash "error" a))))
        (ok (eql 8 (gethash "id" a)))))))

(deftest requests-before-initialize-are-refused
  (multiple-value-bind (ra rc agent) (pair)
    (declare (ignore ra))
    (let ((a (json (acp:acp-handle-message
                    (agent-connection rc)
                    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"session/new\",
                      \"params\":{\"cwd\":\"/w\",\"mcpServers\":[]}}"))))
      (ok (eql -32600 (gethash "code" (gethash "error" a)))))
    (ok (null (acp:acp-handle-message
               (agent-connection rc)
               "{\"jsonrpc\":\"2.0\",\"method\":\"session/cancel\",\"params\":{\"sessionId\":\"s\"}}")))
    (ok (null (agent-event agent :new-session)))
    (ok (null (agent-event agent :cancel)))))
