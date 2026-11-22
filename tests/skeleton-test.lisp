(in-package #:acp-protocol/tests)

(deftest skeleton-protocol-version
  (ok (eql 1 acp-protocol:+acp-protocol-version+)))
