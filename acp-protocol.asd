(defsystem "acp-protocol"
  :version "0.0.0"
  :description "CLOS Agent Client Protocol (ACP v1): message model, agent/client GFs, conditions"
  :author "egao1980"
  :license "MIT"
  :serial t
  :pathname "src"
  :components ((:file "package"))
  :in-order-to ((test-op (test-op "acp-protocol/tests"))))

(defsystem "acp-protocol/tests"
  :depends-on ("acp-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "skeleton-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
