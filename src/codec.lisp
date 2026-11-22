(in-package #:acp-protocol)

;;; Codec (contract ACP-0). GIVEN: the ACP-MESSAGE envelope class and its
;;; constructors. STUBBED: everything that parses, dumps or maps errors.
;;;
;;; JSON is json-protocol's model (objects = EQUAL hash-tables with string
;;; keys, arrays = vectors, null = :NULL, false = NIL). Objects go through
;;; schema-protocol (STACK-SCHEMA:PARSE / DUMP); JSON-RPC envelopes through
;;; rpc-protocol's codec GFs with RPC-PROTOCOL-JSON:*JSONRPC-CODEC*
;;; (RPC-PROTOCOL:ENCODE-REQUEST / -NOTIFICATION / -RESPONSE /
;;; -ERROR-RESPONSE and DECODE-MESSAGE). There is no second JSON-RPC here.
;;;
;;; PARSE-ACP-OBJECT CLASS SOURCE → instance of CLASS (or of the variant its
;;;   tag selects). SOURCE is a hash-table, or a JSON string (decoded first).
;;;   A schema validation failure, a string that is not JSON, or a value that
;;;   is not an object signals ACP-INVALID-PARAMS whose DATA is a hash-table
;;;   with "issues" (a vector of strings) and whose CAUSE is the original
;;;   condition. Unknown fields are kept (extras); an unknown tag selects the
;;;   UNKNOWN-… variant (model.lisp).
;;; ACP-OBJECT-TABLE OBJECT → hash-table: STACK-SCHEMA:DUMP, extras included.
;;;   A hash-table is returned as is.
;;; ENCODE-ACP-OBJECT OBJECT → JSON string of ACP-OBJECT-TABLE.
;;;
;;; DECODE-ACP-MESSAGE SOURCE &key METHOD → ACP-MESSAGE. SOURCE is a JSON-RPC
;;;   text (or an already decoded hash-table).
;;;     "method" + "id"      → :request
;;;     "method", no "id"    → :notification
;;;     "result" + "id"      → :response
;;;     "error"  + "id"      → :error, ERROR = an ACP-ERROR-OBJECT
;;;   For a request / notification of a method in +ACP-METHODS+, PARAMS is
;;;   parsed into that row's request class (absent params parse as {}); for
;;;   any other method (extensions, unknown) PARAMS is the raw value and
;;;   KNOWN-P is NIL. A response's RESULT is parsed into the response class of
;;;   METHOD (the method of the request it answers; a response carries none)
;;;   when METHOD names a request in the table, else it stays raw and KNOWN-P
;;;   is NIL. Not JSON, not an object, or "jsonrpc" not "2.0" → signals
;;;   ACP-INVALID-REQUEST; params / result that do not parse → ACP-INVALID-PARAMS.
;;; ENCODE-ACP-MESSAGE MESSAGE → JSON-RPC text, via the jsonrpc codec, with
;;;   params / result through ACP-OBJECT-TABLE (raw values as they are). A
;;;   decode → encode round trip is JSON-equal to the input for every message
;;;   of the vendored examples (tests/fixtures/v1).
;;;
;;; ACP-ERROR-FOR CONDITION → (values CODE MESSAGE DATA): an ACP-ERROR gives
;;;   its own code, message and data; an RPC-PROTOCOL:RPC-ERROR its code,
;;;   message and data; any other condition -32603 with its printed text and
;;;   data NIL.
;;; ACP-CONDITION-FOR CODE MESSAGE &optional DATA → a condition object (not
;;;   signalled): the first +ACP-ERROR-CODES+ type with CODE, else ACP-ERROR;
;;;   with that :CODE, :MESSAGE and :DATA.

(defclass acp-message ()
  ((kind :initarg :kind :reader acp-message-kind
         :documentation ":request | :notification | :response | :error")
   (id :initarg :id :initform nil :reader acp-message-id)
   (method :initarg :method :initform nil :reader acp-message-method)
   (params :initarg :params :initform nil :reader acp-message-params)
   (result :initarg :result :initform nil :reader acp-message-result)
   (error :initarg :error :initform nil :reader acp-message-error
          :documentation "An ACP-ERROR-OBJECT for :error.")
   (known-p :initarg :known-p :initform t :reader acp-message-known-p
            :documentation "NIL when params / result were left raw (unknown method)."))
  (:documentation "One JSON-RPC 2.0 message of an ACP connection."))

(defmethod print-object ((m acp-message) stream)
  (print-unreadable-object (m stream :type t)
    (format stream "~(~A~)~@[ ~A~]~@[ id=~S~]"
            (acp-message-kind m) (acp-message-method m) (acp-message-id m))))

(defun make-acp-request (method params &key (id 1))
  (make-instance 'acp-message :kind :request :method method :params params :id id
                              :known-p (not (null (acp-method-row method)))))

(defun make-acp-notification (method params)
  (make-instance 'acp-message :kind :notification :method method :params params
                              :known-p (not (null (acp-method-row method)))))

(defun make-acp-response (result &key (id 1) method)
  (make-instance 'acp-message :kind :response :result result :id id :method method
                              :known-p (not (hash-table-p result))))

(defun make-acp-error-response (code message &key (id 1) data)
  (make-instance 'acp-message :kind :error :id id
                              :error (make-acp 'acp-error-object
                                               :code code :message message :data data)))

;;; --- objects --------------------------------------------------------------------

(defun %json-object (&rest kvs)
  (let ((h (make-hash-table :test 'equal)))
    (loop for (k v) on kvs by #'cddr do (setf (gethash k h) v))
    h))

(defun %issue-text (issue)
  (format nil "~:[$~;~:*~{~A~^.~}~]: ~A"
          (stack-schema:schema-issue-path issue)
          (stack-schema:schema-issue-message issue)))

(defun %invalid-params (cause issues)
  "An ACP-INVALID-PARAMS (not signalled) whose DATA carries ISSUES (strings)."
  (make-condition 'acp-invalid-params
                  :cause cause
                  :data (%json-object "issues" (coerce issues 'vector))))

(defun parse-acp-object (class source)
  (check-type class symbol)
  (let ((table (if (stringp source)
                   (handler-case (json-protocol:decode source)
                     (error (e) (error (%invalid-params e (list (princ-to-string e))))))
                   source)))
    (unless (hash-table-p table)
      (error (%invalid-params nil (list (format nil "$: expected a JSON object, got ~A"
                                                (type-of table))))))
    (handler-case (stack-schema:parse class table)
      (stack-schema:schema-validation-error (e)
        (error (%invalid-params
                e (or (mapcar #'%issue-text (stack-schema:schema-validation-error-issues e))
                      (list (princ-to-string e))))))
      ((or stack-schema:schema-error type-error) (e)
        (error (%invalid-params e (list (princ-to-string e))))))))

(defun %schema-object-p (object)
  (and (typep object 'standard-object)
       (stack-schema:schema-class-p (class-of object))))

(defun acp-object-table (object)
  (if (hash-table-p object)
      object
      (stack-schema:dump object)))

(defun %wire (value)
  "VALUE as a JSON value: a model object dumped, anything else as is."
  (if (%schema-object-p value) (stack-schema:dump value) value))

(defun encode-acp-object (object)
  (json-protocol:encode (acp-object-table object)))

;;; --- envelopes ------------------------------------------------------------------

(defun %params-object (params)
  "Absent params (NIL, or the `[]` rpc-protocol-json writes for NIL) → {}."
  (if (or (null params)
          (and (vectorp params) (not (stringp params)) (zerop (length params))))
      (make-hash-table :test 'equal)
      params))

(defun %envelope (source)
  "Phase 1: SOURCE (text or decoded table) → (values TABLE KIND PROBLEM).
KIND is :request :notification :response :error; PROBLEM is NIL, :parse (not
JSON) or :invalid (not a JSON-RPC 2.0 message). Never signals."
  (let ((table (if (hash-table-p source)
                   source
                   (handler-case (rpc-protocol:decode-message
                                  source :codec rpc-protocol-json:*jsonrpc-codec*)
                     (error () (return-from %envelope (values nil nil :parse)))))))
    (unless (and (hash-table-p table) (equal "2.0" (gethash "jsonrpc" table)))
      (return-from %envelope (values nil nil :invalid)))
    (flet ((has (key) (nth-value 1 (gethash key table))))
      (let ((kind (cond ((stringp (gethash "method" table))
                         (if (has "id") :request :notification))
                        ((and (has "id") (has "result")) :response)
                        ((and (has "id") (hash-table-p (gethash "error" table))) :error))))
        (if kind
            (values table kind nil)
            (values nil nil :invalid))))))

(defun %realize (table kind method)
  "Phase 2: an envelope TABLE of KIND → ACP-MESSAGE, payloads parsed."
  (let ((id (gethash "id" table)))
    (ecase kind
      ((:request :notification)
       (let* ((name (gethash "method" table))
              (row (acp-method-row name))
              (params (gethash "params" table)))
         (make-instance 'acp-message
                        :kind kind :id (and (eq kind :request) id) :method name
                        :params (if row
                                    (parse-acp-object (fourth row) (%params-object params))
                                    params)
                        :known-p (and row t))))
      (:response
       (let* ((class (and method (acp-method-response-class method)))
              (result (gethash "result" table)))
         (make-instance 'acp-message
                        :kind :response :id id :method method
                        :result (if class (parse-acp-object class result) result)
                        :known-p (and class t))))
      (:error
       (make-instance 'acp-message
                      :kind :error :id id :method method
                      :error (parse-acp-object 'acp-error-object (gethash "error" table))
                      :known-p t)))))

(defun decode-acp-message (source &key method)
  (multiple-value-bind (table kind problem) (%envelope source)
    (ecase problem
      (:parse (error 'acp-invalid-request :message "Parse error: not JSON"))
      (:invalid (error 'acp-invalid-request :message "Not a JSON-RPC 2.0 message"))
      ((nil) (%realize table kind method)))))

(defun encode-acp-message (message)
  (check-type message acp-message)
  (let ((codec rpc-protocol-json:*jsonrpc-codec*)
        (id (acp-message-id message)))
    (ecase (acp-message-kind message)
      (:request
       (rpc-protocol:encode-request (acp-message-method message)
                                    (%wire (acp-message-params message))
                                    :id id :codec codec))
      (:notification
       (rpc-protocol:encode-notification (acp-message-method message)
                                         (%wire (acp-message-params message))
                                         :codec codec))
      (:response
       (rpc-protocol:encode-response (%wire (acp-message-result message))
                                     :id (or id :null) :codec codec))
      (:error
       (let ((e (acp-message-error message)))
         (rpc-protocol:encode-error-response
          (code e) (message e)
          :id (or id :null)
          :data (and (slot-boundp e 'data) (data e))
          :codec codec))))))

;;; --- error mapping ----------------------------------------------------------------

(defun acp-error-for (condition)
  (typecase condition
    (acp-error (values (acp-error-code condition)
                       (acp-error-message condition)
                       (acp-error-data condition)))
    (rpc-protocol:rpc-error (values (rpc-protocol:rpc-error-code condition)
                                    (or (rpc-protocol:rpc-error-message condition)
                                        (princ-to-string condition))
                                    (rpc-protocol:rpc-error-data condition)))
    (t (values -32603 (princ-to-string condition) nil))))

(defun acp-condition-for (code message &optional data)
  (check-type code integer)
  (make-condition (or (car (rassoc code +acp-error-codes+)) 'acp-error)
                  :code code :message message :data data))
