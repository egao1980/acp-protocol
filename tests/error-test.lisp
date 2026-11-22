(in-package #:acp-protocol/tests)

;;; Error mapping: conditions → codes on the answering side, codes →
;;; conditions on the calling side.

(deftest condition-defaults
  (dolist (row acp:+acp-error-codes+)
    (let ((c (make-condition (car row))))
      (ok (typep c 'acp:acp-error) (d (car row)))
      (ok (eql (cdr row) (acp:acp-error-code c)) (d (car row)))
      (ok (plusp (length (princ-to-string c))) (d (car row)))))
  (ok (eql -32601 (acp:acp-error-code (make-condition 'acp:acp-unsupported :feature :terminal))))
  (ok (typep (make-condition 'acp:acp-unsupported) 'acp:acp-method-not-found))
  (ok (eql -32600 (acp:acp-error-code (make-condition 'acp:acp-version-mismatch :version 2)))))

(deftest-parametrize error-for-conditions
    ((type code)
     ('acp:acp-invalid-request -32600) ('acp:acp-method-not-found -32601)
     ('acp:acp-unsupported -32601) ('acp:acp-invalid-params -32602)
     ('acp:acp-internal-error -32603) ('acp:acp-request-cancelled -32800)
     ('acp:acp-auth-required -32000) ('acp:acp-resource-not-found -32002))
  (multiple-value-bind (c message data)
      (acp:acp-error-for (make-condition type :message "why" :data (js "sessionId" "s")))
    (ok (eql code c) (d type))
    (ok (equal "why" message) (d type))
    (ok (equal "s" (gethash "sessionId" data)) (d type))))

(deftest error-for-other-conditions
  (multiple-value-bind (c message data)
      (acp:acp-error-for (make-condition 'simple-error :format-control "boom ~A"
                                                       :format-arguments '(7)))
    (ok (eql -32603 c))
    (ok (search "boom 7" message))
    (ok (null data)))
  (multiple-value-bind (c message data)
      (acp:acp-error-for (make-condition 'rpc-protocol:rpc-error
                                         :message "custom" :code -31001 :data (js "k" 1)))
    (ok (eql -31001 c))
    (ok (equal "custom" message))
    (ok (eql 1 (gethash "k" data))))
  (multiple-value-bind (c) (acp:acp-error-for (make-condition 'acp:acp-error :code -31500))
    (ok (eql -31500 c))))

(deftest-parametrize condition-for-codes
    ((code type)
     (-32600 'acp:acp-invalid-request) (-32601 'acp:acp-method-not-found)
     (-32602 'acp:acp-invalid-params) (-32603 'acp:acp-internal-error)
     (-32800 'acp:acp-request-cancelled) (-32000 'acp:acp-auth-required)
     (-32002 'acp:acp-resource-not-found) (-31999 'acp:acp-error) (-32700 'acp:acp-error))
  (let ((c (acp:acp-condition-for code "msg" (js "path" "/a"))))
    (ok (eq type (type-of c)) (d code))
    (ok (eql code (acp:acp-error-code c)) (d code))
    (ok (equal "msg" (acp:acp-error-message c)) (d code))
    (ok (equal "/a" (gethash "path" (acp:acp-error-data c))) (d code))))

(deftest condition-for-without-data
  (let ((c (acp:acp-condition-for -32800 "Request cancelled")))
    (ok (typep c 'acp:acp-request-cancelled))
    (ok (null (acp:acp-error-data c)))))
