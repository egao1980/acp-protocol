(in-package #:acp-protocol/tests)

;;; Capabilities: declared at initialize, omitted = unsupported, `{}` = on.

(defparameter *rich-client-caps*
  "{\"fs\":{\"readTextFile\":true,\"writeTextFile\":false},\"terminal\":true,
    \"auth\":{\"terminal\":true},\"plan\":{},\"subagents\":{},
    \"elicitation\":{\"form\":{},\"url\":null},
    \"session\":{\"configOptions\":{\"boolean\":{}},\"compaction\":{},\"notices\":null}}")

(deftest-parametrize client-features
    ((feature expected)
     (:read-text-file t) (:write-text-file nil) (:terminal t) (:auth-terminal t)
     (:plan-operations t) (:subagents t) (:elicitation t) (:elicitation-form t)
     (:elicitation-url nil) (:boolean-config-options t) (:session-compaction t)
     (:session-notices nil))
  (let ((caps (client-caps *rich-client-caps*)))
    (ok (eq expected (and (acp:client-supports-p caps feature) t)) (d feature))
    (ng (acp:client-supports-p (client-caps "{}") feature) (d feature))
    (ng (acp:client-supports-p nil feature) (d feature))))

(defparameter *rich-agent-caps*
  "{\"loadSession\":true,
    \"promptCapabilities\":{\"image\":true,\"audio\":false,\"embeddedContext\":true},
    \"mcpCapabilities\":{\"http\":true},
    \"sessionCapabilities\":{\"list\":{},\"delete\":null,\"resume\":{},\"close\":{},
                            \"additionalDirectories\":{},\"systemPrompt\":{\"mode\":{}}},
    \"auth\":{\"logout\":{}}}")

(deftest-parametrize agent-features
    ((feature expected)
     (:load-session t) (:image t) (:audio nil) (:embedded-context t) (:mcp-http t)
     (:mcp-sse nil) (:session-list t) (:session-delete nil) (:session-resume t)
     (:session-close t) (:additional-directories t) (:system-prompt t) (:logout t))
  (let ((caps (agent-caps-from *rich-agent-caps*)))
    (ok (eq expected (and (acp:agent-supports-p caps feature) t)) (d feature))
    (ng (acp:agent-supports-p (agent-caps-from "{}") feature) (d feature))
    (ng (acp:agent-supports-p nil feature) (d feature))))

(deftest every-listed-feature-is-answered
  (let ((c (client-caps "{}")) (a (agent-caps-from "{}")))
    (dolist (f acp:+acp-client-features+)
      (ok (null (acp:client-supports-p c f)) (d f)))
    (dolist (f acp:+acp-agent-features+)
      (ok (null (acp:agent-supports-p a f)) (d f)))))

(deftest unknown-feature-is-a-programming-error
  (ok (signals (acp:client-supports-p (client-caps "{}") :teleport) 'type-error))
  (ok (signals (acp:agent-supports-p (agent-caps-from "{}") :teleport) 'type-error)))

(deftest capability-meta-on-any-object
  (let ((a (agent-caps-from "{\"loadSession\":true,\"_meta\":{\"com.example/workspace\":true,
                                                          \"com.example/off\":false}}")))
    (ok (eq t (acp:capability-meta a "com.example/workspace")))
    (multiple-value-bind (v found) (acp:capability-meta a "com.example/off")
      (ok (null v))
      (ok found)))
  (multiple-value-bind (v found) (acp:capability-meta (agent-caps-from "{}") "x")
    (ok (null v))
    (ng found)))
