(defpackage #:acp-protocol
  (:use #:cl)
  (:documentation "CLOS Agent Client Protocol (ACP v1, schema 1.34.1): message model,
agent-side and client-side generic functions, conditions and restarts. No transport;
JSON-RPC through rpc-protocol / rpc-protocol-json.")
  (:export
   ;; constants and the method table
   #:+acp-protocol-version+ #:+acp-schema-version+ #:+acp-extension-prefix+
   #:+acp-stop-reasons+ #:+acp-tool-kinds+ #:+acp-tool-call-statuses+
   #:+acp-permission-option-kinds+ #:+acp-methods+ #:+acp-client-features+
   #:+acp-agent-features+ #:+acp-error-codes+
   #:acp-method-row #:acp-method-direction #:acp-method-kind #:acp-method-request-class
   #:acp-method-response-class #:acp-method-function #:acp-method-capability
   #:acp-extension-method-p
   ;; conditions and restarts
   #:acp-error #:acp-error-code #:acp-error-message #:acp-error-data #:acp-error-cause
   #:acp-invalid-request #:acp-method-not-found #:acp-error-method #:acp-unsupported
   #:acp-unsupported-feature #:acp-invalid-params #:acp-internal-error
   #:acp-request-cancelled #:acp-auth-required #:acp-resource-not-found
   #:acp-version-mismatch #:acp-version-mismatch-version
   #:acp-permission-required #:acp-permission-required-request
   #:acp-permission-required-connection
   #:select-permission-option #:allow-once #:allow-always #:reject-once #:reject-always
   #:cancel-permission
   #:invoke-select-permission-option #:invoke-allow-once #:invoke-allow-always
   #:invoke-reject-once #:invoke-reject-always #:invoke-cancel-permission
   #:retry #:invoke-retry #:invoke-use-value
   ;; model: constructor, classes, accessors
   #:make-acp #:defacp
   #:implementation #:annotations #:acp-error-object #:content-block #:text-content
   #:image-content #:audio-content #:resource-link #:text-resource-contents
   #:blob-resource-contents #:embedded-resource #:unknown-content-block
   #:file-system-capabilities #:auth-capabilities #:client-session-capabilities
   #:elicitation-capabilities #:client-capabilities #:prompt-capabilities
   #:mcp-capabilities #:session-capabilities #:agent-auth-capabilities
   #:agent-capabilities #:auth-method-terminal #:auth-method-agent #:initialize-request
   #:initialize-response #:authenticate-request #:authenticate-response #:logout-request
   #:logout-response #:env-variable #:http-header #:mcp-server-http #:mcp-server-sse
   #:mcp-server-stdio #:system-prompt #:session-mode #:session-mode-state
   #:session-config-select-option #:session-config-select-group #:session-config-option
   #:new-session-request #:new-session-response #:load-session-request
   #:load-session-response #:resume-session-request #:resume-session-response
   #:list-sessions-request #:session-info #:list-sessions-response
   #:delete-session-request #:delete-session-response #:close-session-request
   #:close-session-response #:set-session-mode-request #:set-session-mode-response
   #:set-session-config-option-request #:set-session-config-option-response
   #:prompt-request #:prompt-response #:cancel-notification #:cancel-request-notification
   #:tool-call-location #:tool-call-content #:content #:diff #:terminal
   #:session-reference #:unknown-tool-call-content #:tool-call #:tool-call-update
   #:content-chunk #:plan-entry #:plan #:plan-update-content #:plan-items #:plan-markdown
   #:unknown-plan-update-content #:unstructured-command-input #:available-command #:cost
   #:session-update #:update-user-message-chunk #:update-agent-message-chunk
   #:update-agent-thought-chunk #:update-tool-call #:update-tool-call-update
   #:update-plan #:update-plan-update #:update-plan-removed
   #:update-available-commands-update #:update-current-mode-update
   #:update-config-option-update #:update-session-info-update #:update-usage-update
   #:update-notice #:update-compaction-update #:update-compaction-summary-chunk
   #:update-subagent-update #:update-session-message #:update-session-message-chunk
   #:unknown-session-update #:session-notification #:permission-option
   #:request-permission-request #:request-permission-outcome
   #:cancelled-permission-outcome #:selected-permission-outcome
   #:request-permission-response #:read-text-file-request #:read-text-file-response
   #:write-text-file-request #:write-text-file-response #:terminal-exit-status
   #:create-terminal-request #:create-terminal-response #:terminal-output-request
   #:terminal-output-response #:release-terminal-request #:release-terminal-response
   #:wait-for-terminal-exit-request #:wait-for-terminal-exit-response
   #:kill-terminal-request #:kill-terminal-response #:create-elicitation-request
   #:create-elicitation-response #:complete-elicitation-notification
   ;; accessors (slot names)
   #:action #:additional-directories #:agent-info #:amount #:args #:audience #:audio
   #:auth #:auth-methods #:available-commands #:available-modes #:blob #:capabilities
   #:category #:client-info #:code #:command #:compaction #:compaction-id #:config-id
   #:config-options #:currency #:current-mode-id #:current-value #:cursor #:cwd #:data
   #:description #:elicitation #:elicitation-id #:embedded-context #:entries #:env
   #:exit-code #:exit-signal #:exit-status #:failure #:form #:fs #:group #:headers #:hint
   #:http #:id #:image #:input #:kind #:last-modified #:limit #:line #:load-session
   #:locations #:logout #:mcp-servers #:message #:message-id #:meta #:method-id
   #:mime-type #:mode #:mode-id #:modes #:name #:new-text #:next-cursor #:notices
   #:old-text #:option-id #:options #:outcome #:output #:output-byte-limit #:path
   #:plan-id #:priority #:prompt #:protocol-version #:raw-input #:raw-output
   #:read-text-file #:recipient-message-id #:recipient-session-id #:request-id
   #:requested-schema #:resource #:resume #:sender-message-id #:sender-session-id
   #:session #:session-close #:session-delete #:session-id #:session-list #:sessions
   #:severity #:size #:sse #:state #:status #:stop-reason #:subagents #:summary
   #:terminal-id #:text #:title #:tool-call-id #:truncated #:update #:updated-at #:uri
   #:url #:used #:value #:version #:wire-type #:write-text-file
   ;; codec
   #:acp-message #:acp-message-kind #:acp-message-id #:acp-message-method
   #:acp-message-params #:acp-message-result #:acp-message-error #:acp-message-known-p
   #:make-acp-request #:make-acp-notification #:make-acp-response #:make-acp-error-response
   #:parse-acp-object #:acp-object-table #:encode-acp-object
   #:decode-acp-message #:encode-acp-message #:acp-error-for #:acp-condition-for
   ;; capabilities
   #:client-supports-p #:agent-supports-p #:capability-meta
   ;; peers and connections
   #:*acp-connection* #:*acp-remote* #:*acp-incoming-kind*
   #:acp-peer #:acp-peer-info #:acp-agent #:acp-client #:remote-peer #:remote-connection
   #:remote-agent #:remote-client
   #:acp-connection #:make-acp-connection #:acp-connection-role #:acp-connection-local
   #:acp-connection-transport #:acp-connection-remote #:acp-connection-initialized-p
   #:acp-connection-protocol-version #:acp-connection-client-capabilities
   #:acp-connection-client-info #:acp-connection-agent-capabilities
   #:acp-connection-agent-info
   #:acp-connection-handler #:acp-handle-message #:remote-call #:remote-notify
   ;; agent-side GFs
   #:acp-initialize #:acp-authenticate #:acp-logout #:acp-new-session #:acp-load-session
   #:acp-list-sessions #:acp-delete-session #:acp-resume-session #:acp-close-session
   #:acp-set-session-mode #:acp-set-session-config-option #:acp-prompt #:acp-cancel
   ;; client-side GFs
   #:acp-request-permission #:acp-session-update #:acp-read-text-file
   #:acp-write-text-file #:acp-create-terminal #:acp-terminal-output
   #:acp-release-terminal #:acp-wait-for-terminal-exit #:acp-kill-terminal
   #:acp-create-elicitation #:acp-complete-elicitation
   ;; both sides, extensions
   #:acp-cancel-request #:acp-ext-method #:acp-ext-notification
   ;; helpers
   #:acp-send-update #:acp-ask-permission #:acp-call-ext #:acp-notify-ext
   ;; loopback
   #:loopback-rpc-transport #:make-acp-loopback #:acp-loopback-log))

(in-package #:acp-protocol)

(define-condition acp0-pending (error)
  ((what :initarg :what :reader acp0-pending-what))
  (:report (lambda (c s)
             (format s "ACP-0 contract stub not implemented: ~S" (acp0-pending-what c)))))

(defun %acp0-pending (what)
  "Contract stub. Every call site is replaced by the ACP-0 implementation."
  (error 'acp0-pending :what what))
