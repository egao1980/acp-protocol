(defpackage #:acp-protocol
  (:use #:cl)
  (:export #:+acp-protocol-version+))

(in-package #:acp-protocol)

;;; Skeleton. The ACP-0 contract (0.1.0) lands on its own branch; see
;;; cl-stack/docs/capabilities/acp.md.

(defconstant +acp-protocol-version+ 1
  "The ACP major protocol version this package speaks (initialize protocolVersion).")
