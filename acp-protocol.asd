(defsystem "acp-protocol"
  :version "0.1.0"
  :description "CLOS Agent Client Protocol (ACP v1): message model, agent/client GFs, conditions"
  :author "egao1980"
  :license "MIT"
  :depends-on ((:version "rpc-protocol" "0.2.0")
               (:version "rpc-protocol-json" "0.1.1")
               "json-protocol" "json-backend-jzon"
               (:version "schema-protocol" "0.2.2")
               "bordeaux-threads")
  :properties (:cl-repo (:ci (:with ("dissect"))))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "constants")
               (:file "model")
               (:file "conditions")
               (:file "codec")
               (:file "capabilities")
               (:file "peer")
               (:file "loopback"))
  :in-order-to ((test-op (test-op "acp-protocol/tests"))))

(defsystem "acp-protocol/tests"
  :depends-on ("acp-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "support")
               (:file "model-test")
               (:file "tolerance-test")
               (:file "capability-test")
               (:file "error-test")
               (:file "loopback-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
