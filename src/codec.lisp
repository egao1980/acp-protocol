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

(defun parse-acp-object (class source)
  (declare (ignore class source))
  (%acp0-pending 'parse-acp-object))

(defun acp-object-table (object)
  (declare (ignore object))
  (%acp0-pending 'acp-object-table))

(defun encode-acp-object (object)
  (declare (ignore object))
  (%acp0-pending 'encode-acp-object))

(defun decode-acp-message (source &key method)
  (declare (ignore source method))
  (%acp0-pending 'decode-acp-message))

(defun encode-acp-message (message)
  (declare (ignore message))
  (%acp0-pending 'encode-acp-message))

(defun acp-error-for (condition)
  (declare (ignore condition))
  (%acp0-pending 'acp-error-for))

(defun acp-condition-for (code message &optional data)
  (declare (ignore code message data))
  (%acp0-pending 'acp-condition-for))
