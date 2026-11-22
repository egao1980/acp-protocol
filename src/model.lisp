(in-package #:acp-protocol)

;;; ACP v1 message model (GIVEN, contract ACP-0).
;;;
;;; Pinned to the stable schema of agentclientprotocol/agent-client-protocol
;;; release schema-v1.34.1 (schema/v1/schema.json, protocolVersion 1). Only
;;; the stable schema is modelled; schema.unstable.json (providers/*,
;;; session/fork, session/status, mcp/message, proxy/*, …) is deferred.
;;;
;;; Rules (the codec and the tests rely on them):
;;;
;;; * Class name = the kebab-case of the schema $defs name (TextContent →
;;;   TEXT-CONTENT). Exceptions: `Error` → ACP-ERROR-OBJECT (CL:ERROR is
;;;   locked); a SessionUpdate variant is UPDATE-<its sessionUpdate tag>
;;;   (`tool_call_update` → UPDATE-TOOL-CALL-UPDATE), because the same
;;;   payload def is reused by several tags (ContentChunk) or outside the
;;;   union (ToolCallUpdate in session/request_permission).
;;; * Slot name = kebab-case of the wire key, wire key = camelCase
;;;   (:key-style :camel). Wire keys whose kebab name is a CL symbol get
;;;   another slot name and an explicit :key: "type" → WIRE-TYPE, "error" →
;;;   FAILURE, "signal" → EXIT-SIGNAL, "list" / "delete" / "close" (session
;;;   capabilities) → SESSION-LIST / SESSION-DELETE / SESSION-CLOSE.
;;;   "_meta" → META on every class. The accessor is the slot name.
;;; * Every class is (:extra :allow): unknown fields are kept in
;;;   SCHEMA-EXTRAS and dumped back verbatim, so a newer peer's fields
;;;   survive a round trip (the spec reserves root names for future
;;;   versions; peers MUST tolerate them).
;;; * Optional fields are unbound when absent, so DUMP omits them. JSON null
;;;   is :NULL (json-protocol); a nullable field is typed (OR … NULL).
;;; * Open enums (stopReason, ToolKind, ToolCallStatus, PermissionOptionKind,
;;;   NoticeSeverity, CompactionStatus, SystemPromptMode, config categories,
;;;   plan priorities/statuses, roles) are STRINGs. Unknown values are kept;
;;;   the known ones are listed in constants.lisp.
;;; * Tagged unions are a base class with a :tag slot and an ordered variant
;;;   list ending in an UNKNOWN-… fallback whose tag slot is any STRING: an
;;;   unknown kind parses to the fallback, keeps every field in its extras
;;;   and dumps back verbatim (ContentBlock, ToolCallContent,
;;;   PlanUpdateContent, SessionUpdate). RequestPermissionOutcome is closed.
;;; * Untagged unions (McpServer, AuthMethod, EmbeddedResource's resource)
;;;   are (OR …) slot types; a variant whose discriminator is required has
;;;   no :default (an MCP-SERVER-HTTP must be made with :WIRE-TYPE "http").
;;; * Deeply open structures are kept as raw JSON (HASH-TABLE or T):
;;;   ElicitationSchema (requestedSchema), StateUpdate (subagent state),
;;;   SubagentSessionCapabilities, SessionConfigOption options,
;;;   CompactionUpdate summary, rawInput / rawOutput, and the capability
;;;   objects whose only content is _meta (`{}` = supported).

(defmacro defacp (name supers &body body)
  "STACK-SCHEMA:DEFSCHEMA with the ACP defaults: an optional `_meta` slot,
camelCase wire keys and unknown fields kept. A leading docstring is kept."
  (let ((doc (when (stringp (first body)) (list (pop body)))))
    `(stack-schema:defschema ,name ,supers
       ,@doc
       (meta (or hash-table null) :key "_meta" :optional t)
       ,@body
       (:key-style :camel)
       (:extra :allow))))

;;; --- shared -----------------------------------------------------------------

(defacp implementation ()
  "Implementation information (clientInfo / agentInfo)."
  (name string)
  (title (or string null) :optional t)
  (version string))

(defacp annotations ()
  (audience (or (vector string) null) :optional t)
  (last-modified (or string null) :optional t)
  (priority (or number null) :optional t))

(defacp acp-error-object ()
  "A JSON-RPC error object (schema `Error`)."
  (code integer)
  (message string)
  (data t :optional t))

;;; --- content ----------------------------------------------------------------

(defacp content-block ()
  "ContentBlock: discriminated by `type`."
  (wire-type string :key "type")
  (:tag wire-type
        text-content image-content audio-content resource-link embedded-resource
        unknown-content-block))

(defacp text-content (content-block)
  (wire-type (eql "text") :default "text" :key "type")
  (annotations (or annotations null) :optional t)
  (text string))

(defacp image-content (content-block)
  (wire-type (eql "image") :default "image" :key "type")
  (annotations (or annotations null) :optional t)
  (data string)
  (mime-type string)
  (uri (or string null) :optional t))

(defacp audio-content (content-block)
  (wire-type (eql "audio") :default "audio" :key "type")
  (annotations (or annotations null) :optional t)
  (data string)
  (mime-type string))

(defacp resource-link (content-block)
  (wire-type (eql "resource_link") :default "resource_link" :key "type")
  (annotations (or annotations null) :optional t)
  (description (or string null) :optional t)
  (mime-type (or string null) :optional t)
  (name string)
  (size (or integer null) :optional t)
  (title (or string null) :optional t)
  (uri string))

(defacp text-resource-contents ()
  (mime-type (or string null) :optional t)
  (text string)
  (uri string))

(defacp blob-resource-contents ()
  (blob string)
  (mime-type (or string null) :optional t)
  (uri string))

(defacp embedded-resource (content-block)
  (wire-type (eql "resource") :default "resource" :key "type")
  (annotations (or annotations null) :optional t)
  (resource (or text-resource-contents blob-resource-contents)))

(defacp unknown-content-block (content-block)
  "A content block of a type this build does not model; fields in extras."
  (wire-type string :key "type"))

;;; --- capabilities -----------------------------------------------------------

(defacp file-system-capabilities ()
  (read-text-file boolean :optional t)
  (write-text-file boolean :optional t))

(defacp auth-capabilities ()
  (terminal boolean :optional t))

(defacp client-session-capabilities ()
  (compaction (or hash-table null) :optional t)
  (config-options (or hash-table null) :optional t)
  (notices (or hash-table null) :optional t))

(defacp elicitation-capabilities ()
  (form (or hash-table null) :optional t)
  (url (or hash-table null) :optional t))

(defacp client-capabilities ()
  (fs file-system-capabilities :optional t)
  (terminal boolean :optional t)
  (session (or client-session-capabilities null) :optional t)
  (subagents (or hash-table null) :optional t)
  (plan (or hash-table null) :optional t)
  (auth auth-capabilities :optional t)
  (elicitation (or elicitation-capabilities null) :optional t))

(defacp prompt-capabilities ()
  (image boolean :optional t)
  (audio boolean :optional t)
  (embedded-context boolean :optional t))

(defacp mcp-capabilities ()
  (http boolean :optional t)
  (sse boolean :optional t))

(defacp session-capabilities ()
  (session-list (or hash-table null) :key "list" :optional t)
  (session-delete (or hash-table null) :key "delete" :optional t)
  (additional-directories (or hash-table null) :optional t)
  (system-prompt (or hash-table null) :optional t)
  (resume (or hash-table null) :optional t)
  (session-close (or hash-table null) :key "close" :optional t))

(defacp agent-auth-capabilities ()
  (logout (or hash-table null) :optional t))

(defacp agent-capabilities ()
  (load-session boolean :optional t)
  (prompt-capabilities prompt-capabilities :optional t)
  (mcp-capabilities mcp-capabilities :optional t)
  (session-capabilities session-capabilities :optional t)
  (auth agent-auth-capabilities :optional t))

;;; --- initialize / auth ------------------------------------------------------

(defacp auth-method-terminal ()
  "AuthMethod with type \"terminal\" (make it with :WIRE-TYPE \"terminal\")."
  (wire-type (eql "terminal") :key "type")
  (id string)
  (name string)
  (description (or string null) :optional t)
  (args (vector string) :optional t)
  (env hash-table :optional t))

(defacp auth-method-agent ()
  "AuthMethod without a type: the agent runs its own login flow."
  (id string)
  (name string)
  (description (or string null) :optional t))

(defacp initialize-request ()
  (protocol-version integer)
  (client-capabilities client-capabilities :optional t)
  (client-info (or implementation null) :optional t))

(defacp initialize-response ()
  (protocol-version integer)
  (agent-capabilities agent-capabilities :optional t)
  (auth-methods (vector (or auth-method-terminal auth-method-agent)) :optional t)
  (agent-info (or implementation null) :optional t))

(defacp authenticate-request ()
  (method-id string))

(defacp authenticate-response ())

(defacp logout-request ())

(defacp logout-response ())

;;; --- session setup ----------------------------------------------------------

(defacp env-variable ()
  (name string)
  (value string))

(defacp http-header ()
  (name string)
  (value string))

(defacp mcp-server-http ()
  (wire-type (eql "http") :key "type")
  (name string)
  (url string)
  (headers (vector http-header)))

(defacp mcp-server-sse ()
  (wire-type (eql "sse") :key "type")
  (name string)
  (url string)
  (headers (vector http-header)))

(defacp mcp-server-stdio ()
  (name string)
  (command string)
  (args (vector string))
  (env (vector env-variable)))

(defacp system-prompt ()
  (mode string)
  (content (vector content-block)))

(defacp session-mode ()
  (id string)
  (name string)
  (description (or string null) :optional t))

(defacp session-mode-state ()
  (current-mode-id string)
  (available-modes (vector session-mode)))

(defacp session-config-select-option ()
  (value string)
  (name string)
  (description (or string null) :optional t))

(defacp session-config-select-group ()
  (group string)
  (name string)
  (options (vector session-config-select-option)))

(defacp session-config-option ()
  "One config option. WIRE-TYPE \"select\" (CURRENT-VALUE a value id,
OPTIONS options or groups, raw) or \"boolean\" (CURRENT-VALUE T / NIL)."
  (id string)
  (name string)
  (description (or string null) :optional t)
  (category (or string null) :optional t)
  (wire-type string :key "type")
  (current-value t)
  (options t :optional t))

(defacp new-session-request ()
  (cwd string)
  (additional-directories (vector string) :optional t)
  (mcp-servers (vector (or mcp-server-http mcp-server-sse mcp-server-stdio)))
  (system-prompt (or system-prompt null) :optional t))

(defacp new-session-response ()
  (session-id string)
  (modes (or session-mode-state null) :optional t)
  (config-options (or (vector session-config-option) null) :optional t))

(defacp load-session-request ()
  (mcp-servers (vector (or mcp-server-http mcp-server-sse mcp-server-stdio)))
  (cwd string)
  (additional-directories (vector string) :optional t)
  (session-id string)
  (system-prompt (or system-prompt null) :optional t))

(defacp load-session-response ()
  (modes (or session-mode-state null) :optional t)
  (config-options (or (vector session-config-option) null) :optional t))

(defacp resume-session-request ()
  (session-id string)
  (cwd string)
  (additional-directories (vector string) :optional t)
  (mcp-servers (vector (or mcp-server-http mcp-server-sse mcp-server-stdio)) :optional t)
  (system-prompt (or system-prompt null) :optional t))

(defacp resume-session-response ()
  (modes (or session-mode-state null) :optional t)
  (config-options (or (vector session-config-option) null) :optional t))

(defacp list-sessions-request ()
  (cwd (or string null) :optional t)
  (cursor (or string null) :optional t))

(defacp session-info ()
  (session-id string)
  (cwd string)
  (additional-directories (vector string) :optional t)
  (title (or string null) :optional t)
  (updated-at (or string null) :optional t))

(defacp list-sessions-response ()
  (sessions (vector session-info))
  (next-cursor (or string null) :optional t))

(defacp delete-session-request ()
  (session-id string))

(defacp delete-session-response ())

(defacp close-session-request ()
  (session-id string))

(defacp close-session-response ())

(defacp set-session-mode-request ()
  (session-id string)
  (mode-id string))

(defacp set-session-mode-response ())

(defacp set-session-config-option-request ()
  "VALUE is a value id (string), or a boolean with WIRE-TYPE \"boolean\"."
  (session-id string)
  (config-id string)
  (wire-type string :key "type" :optional t)
  (value t))

(defacp set-session-config-option-response ()
  (config-options (vector session-config-option)))

;;; --- prompt turn ------------------------------------------------------------

(defacp prompt-request ()
  (session-id string)
  (prompt (vector content-block)))

(defacp prompt-response ()
  (stop-reason string))

(defacp cancel-notification ()
  "session/cancel."
  (session-id string))

(defacp cancel-request-notification ()
  "$/cancel_request."
  (request-id (or null integer string)))

;;; --- session/update ---------------------------------------------------------

(defacp tool-call-location ()
  (path string)
  (line (or integer null) :optional t))

(defacp tool-call-content ()
  "ToolCallContent: discriminated by `type`."
  (wire-type string :key "type")
  (:tag wire-type content diff terminal session-reference unknown-tool-call-content))

(defacp content (tool-call-content)
  (wire-type (eql "content") :default "content" :key "type")
  (content content-block))

(defacp diff (tool-call-content)
  (wire-type (eql "diff") :default "diff" :key "type")
  (path string)
  (old-text (or string null) :optional t)
  (new-text string))

(defacp terminal (tool-call-content)
  (wire-type (eql "terminal") :default "terminal" :key "type")
  (terminal-id string))

(defacp session-reference (tool-call-content)
  (wire-type (eql "session") :default "session" :key "type")
  (session-id string))

(defacp unknown-tool-call-content (tool-call-content)
  (wire-type string :key "type"))

(defacp tool-call ()
  "ToolCall payload (the tool_call update)."
  (tool-call-id string)
  (title string)
  (name (or string null) :optional t)
  (kind string :optional t)
  (status string :optional t)
  (content (vector tool-call-content) :optional t)
  (locations (vector tool-call-location) :optional t)
  (raw-input t :optional t)
  (raw-output t :optional t))

(defacp tool-call-update ()
  "ToolCallUpdate payload: the tool_call_update update, and the toolCall of
session/request_permission. Omitted fields are unchanged."
  (tool-call-id string)
  (kind (or string null) :optional t)
  (status (or string null) :optional t)
  (title (or string null) :optional t)
  (name (or string null) :optional t)
  (content (or (vector tool-call-content) null) :optional t)
  (locations (or (vector tool-call-location) null) :optional t)
  (raw-input t :optional t)
  (raw-output t :optional t))

(defacp content-chunk ()
  (content content-block)
  (message-id (or string null) :optional t))

(defacp plan-entry ()
  (content string)
  (priority string)
  (status string))

(defacp plan ()
  "Plan payload (the plan update): the full checklist."
  (entries (vector plan-entry)))

(defacp plan-update-content ()
  "PlanUpdateContent: discriminated by `type`."
  (wire-type string :key "type")
  (:tag wire-type plan-items plan-markdown unknown-plan-update-content))

(defacp plan-items (plan-update-content)
  (wire-type (eql "items") :default "items" :key "type")
  (plan-id string)
  (entries (vector plan-entry)))

(defacp plan-markdown (plan-update-content)
  (wire-type (eql "markdown") :default "markdown" :key "type")
  (plan-id string)
  (content string)
  (path (or string null) :optional t))

(defacp unknown-plan-update-content (plan-update-content)
  (wire-type string :key "type"))

(defacp unstructured-command-input ()
  (hint string))

(defacp available-command ()
  (name string)
  (description string)
  (input (or unstructured-command-input null) :optional t))

(defacp cost ()
  (amount number)
  (currency string))

(defacp session-update ()
  "SessionUpdate: discriminated by `sessionUpdate`."
  (session-update string)
  (:tag session-update
        update-user-message-chunk update-agent-message-chunk update-agent-thought-chunk
        update-tool-call update-tool-call-update
        update-plan update-plan-update update-plan-removed
        update-available-commands-update update-current-mode-update
        update-config-option-update update-session-info-update update-usage-update
        update-notice update-compaction-update update-compaction-summary-chunk
        update-subagent-update update-session-message update-session-message-chunk
        unknown-session-update))

(defacp update-user-message-chunk (session-update content-chunk)
  (session-update (eql "user_message_chunk") :default "user_message_chunk"))

(defacp update-agent-message-chunk (session-update content-chunk)
  (session-update (eql "agent_message_chunk") :default "agent_message_chunk"))

(defacp update-agent-thought-chunk (session-update content-chunk)
  (session-update (eql "agent_thought_chunk") :default "agent_thought_chunk"))

(defacp update-tool-call (session-update tool-call)
  (session-update (eql "tool_call") :default "tool_call"))

(defacp update-tool-call-update (session-update tool-call-update)
  (session-update (eql "tool_call_update") :default "tool_call_update"))

(defacp update-plan (session-update plan)
  (session-update (eql "plan") :default "plan"))

(defacp update-plan-update (session-update)
  "Plan operation: create or replace one plan (client capability `plan`)."
  (session-update (eql "plan_update") :default "plan_update")
  (plan plan-update-content))

(defacp update-plan-removed (session-update)
  "Plan operation: remove one plan (client capability `plan`)."
  (session-update (eql "plan_removed") :default "plan_removed")
  (plan-id string))

(defacp update-available-commands-update (session-update)
  (session-update (eql "available_commands_update") :default "available_commands_update")
  (available-commands (vector available-command)))

(defacp update-current-mode-update (session-update)
  (session-update (eql "current_mode_update") :default "current_mode_update")
  (current-mode-id string))

(defacp update-config-option-update (session-update)
  (session-update (eql "config_option_update") :default "config_option_update")
  (config-options (vector session-config-option)))

(defacp update-session-info-update (session-update)
  (session-update (eql "session_info_update") :default "session_info_update")
  (title (or string null) :optional t)
  (updated-at (or string null) :optional t))

(defacp update-usage-update (session-update)
  (session-update (eql "usage_update") :default "usage_update")
  (used integer)
  (size integer)
  (cost (or cost null) :optional t))

(defacp update-notice (session-update)
  (session-update (eql "notice") :default "notice")
  (severity string)
  (title string)
  (description (or string null) :optional t))

(defacp update-compaction-update (session-update)
  (session-update (eql "compaction_update") :default "compaction_update")
  (compaction-id string)
  (status string)
  (summary t :optional t)
  (failure (or string null) :key "error" :optional t))

(defacp update-compaction-summary-chunk (session-update)
  (session-update (eql "compaction_summary_chunk") :default "compaction_summary_chunk")
  (compaction-id string)
  (content content-block))

(defacp update-subagent-update (session-update)
  (session-update (eql "subagent_update") :default "subagent_update")
  (session-id string)
  (title (or string null) :optional t)
  (description (or string null) :optional t)
  (capabilities (or hash-table null) :optional t)
  (state (or hash-table null) :optional t)
  (cwd (or string null) :optional t)
  (additional-directories t :optional t))

(defacp update-session-message (session-update)
  (session-update (eql "session_message") :default "session_message")
  (message-id string)
  (sender-session-id (or string null) :optional t)
  (recipient-session-id (or string null) :optional t)
  (sender-message-id (or string null) :optional t)
  (recipient-message-id (or string null) :optional t)
  (content (or (vector content-block) null) :optional t))

(defacp update-session-message-chunk (session-update)
  (session-update (eql "session_message_chunk") :default "session_message_chunk")
  (message-id string)
  (content content-block))

(defacp unknown-session-update (session-update)
  "A session/update kind this build does not model; fields in extras."
  (session-update string))

(defacp session-notification ()
  "session/update params."
  (session-id string)
  (update session-update))

;;; --- permission -------------------------------------------------------------

(defacp permission-option ()
  (option-id string)
  (name string)
  (kind string))

(defacp request-permission-request ()
  (session-id string)
  (tool-call tool-call-update)
  (options (vector permission-option)))

(defacp request-permission-outcome ()
  "RequestPermissionOutcome: discriminated by `outcome`."
  (outcome string)
  (:tag outcome cancelled-permission-outcome selected-permission-outcome))

(defacp cancelled-permission-outcome (request-permission-outcome)
  (outcome (eql "cancelled") :default "cancelled"))

(defacp selected-permission-outcome (request-permission-outcome)
  (outcome (eql "selected") :default "selected")
  (option-id string))

(defacp request-permission-response ()
  (outcome request-permission-outcome))

;;; --- file system ------------------------------------------------------------

(defacp read-text-file-request ()
  (session-id string)
  (path string)
  (line (or integer null) :optional t)
  (limit (or integer null) :optional t))

(defacp read-text-file-response ()
  (content string))

(defacp write-text-file-request ()
  (session-id string)
  (path string)
  (content string))

(defacp write-text-file-response ())

;;; --- terminals --------------------------------------------------------------

(defacp terminal-exit-status ()
  (exit-code (or integer null) :optional t)
  (exit-signal (or string null) :key "signal" :optional t))

(defacp create-terminal-request ()
  (session-id string)
  (command string)
  (args (vector string) :optional t)
  (env (vector env-variable) :optional t)
  (cwd (or string null) :optional t)
  (output-byte-limit (or integer null) :optional t))

(defacp create-terminal-response ()
  (terminal-id string))

(defacp terminal-output-request ()
  (session-id string)
  (terminal-id string))

(defacp terminal-output-response ()
  (output string)
  (truncated boolean)
  (exit-status (or terminal-exit-status null) :optional t))

(defacp release-terminal-request ()
  (session-id string)
  (terminal-id string))

(defacp release-terminal-response ())

(defacp wait-for-terminal-exit-request ()
  (session-id string)
  (terminal-id string))

(defacp wait-for-terminal-exit-response ()
  (exit-code (or integer null) :optional t)
  (exit-signal (or string null) :key "signal" :optional t))

(defacp kill-terminal-request ()
  (session-id string)
  (terminal-id string))

(defacp kill-terminal-response ())

;;; --- elicitation ------------------------------------------------------------

(defacp create-elicitation-request ()
  "elicitation/create, flattened: MODE \"form\" (REQUESTED-SCHEMA, raw) or
\"url\" (ELICITATION-ID, URL), scoped to a session (SESSION-ID, TOOL-CALL-ID)
or a request (REQUEST-ID)."
  (message string)
  (mode string)
  (requested-schema hash-table :optional t)
  (elicitation-id string :optional t)
  (url string :optional t)
  (session-id string :optional t)
  (tool-call-id (or string null) :optional t)
  (request-id (or null integer string) :optional t))

(defacp create-elicitation-response ()
  (action string)
  (content (or hash-table null) :optional t))

(defacp complete-elicitation-notification ()
  (elicitation-id string))

;;; --- constructor ------------------------------------------------------------

(defun make-acp (class &rest initargs)
  "MAKE-INSTANCE of an ACP model CLASS, dropping NIL initargs so the field is
omitted on the wire (unbound). Pass :NULL for an explicit JSON null and a
boolean field's NIL through the slot (SETF) when false must be sent."
  (apply #'make-instance class
         (loop for (k v) on initargs by #'cddr
               when v append (list k v))))
