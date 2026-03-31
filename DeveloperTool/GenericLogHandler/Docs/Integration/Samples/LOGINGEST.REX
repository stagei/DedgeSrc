/* LOGINGEST.REX — Send log entries to GenericLogHandler ingest API      */
/*                                                                       */
/* Fire-and-forget logging from REXX programs. Uses curl.exe for the     */
/* HTTP POST (available on Windows 10+/Server 2019+).                    */
/*                                                                       */
/* Usage:                                                                */
/*   call SendLog "Order processed", "INFO", "OrderModule"               */
/*   call SendLog "Import failed", "ERROR", "WKSTYR", "ERR-42"          */
/*   call SendLogJob "NightlyBatch", "Started", "Batch starting"         */
/*   call SendLogJob "NightlyBatch", "Completed", "150 records done"     */
/*                                                                       */
/* Configuration: change BaseUrl below to match your environment.        */
/*───────────────────────────────────────────────────────────────────────*/

BaseUrl = "http://dedge-server/GenericLogHandler"
Source  = "REXX-Program"

/*───────────────────────────────────────────────────────────────────────*/
/* EXAMPLES                                                              */
/*───────────────────────────────────────────────────────────────────────*/

/* Simple info message */
call SendLog "LOGINGEST.REX sample started", "INFO", "LOGINGEST-Sample"

/* Error with error ID */
call SendLog "File not found: DATAFILE.DAT", "ERROR", "LOGINGEST-Sample", "FILE-404"

/* Job lifecycle tracking */
call SendLogJob "SampleBatch", "Started",   "Processing input files"
call SendLogJob "SampleBatch", "Completed", "Processed 250 records"

/* Warning */
call SendLog "Disk space below 10%", "WARN", "LOGINGEST-Sample"

say "All sample log entries sent."
exit 0


/*───────────────────────────────────────────────────────────────────────*/
/* SendLog: Send a single log entry                                      */
/*   msg     = Log message text (required)                               */
/*   level   = DEBUG/INFO/WARN/ERROR/FATAL (default: INFO)               */
/*   src     = Source identifier (default: Source variable)               */
/*   errorId = Optional error identifier                                 */
/*───────────────────────────────────────────────────────────────────────*/
SendLog: procedure expose BaseUrl Source
  parse arg msg, level, src, errorId

  if strip(level) = "" then level = "INFO"
  if strip(src)   = "" then src = Source

  /* Build JSON payload */
  json = '{"message":"' || EscapeJson(strip(msg))   || '"'
  json = json || ',"level":"'  || strip(level)       || '"'
  json = json || ',"source":"' || EscapeJson(strip(src)) || '"'
  json = json || ',"computerName":"' || GetHostName() || '"'

  if strip(errorId) \= "" then
    json = json || ',"errorId":"' || EscapeJson(strip(errorId)) || '"'

  json = json || '}'

  call PostToApi json
  return


/*───────────────────────────────────────────────────────────────────────*/
/* SendLogJob: Send a log entry with job tracking fields                 */
/*   jobName   = Name of the job/batch                                   */
/*   jobStatus = Started / Completed / Failed / Running                  */
/*   msg       = Log message text                                        */
/*───────────────────────────────────────────────────────────────────────*/
SendLogJob: procedure expose BaseUrl Source
  parse arg jobName, jobStatus, msg

  if strip(msg) = "" then msg = strip(jobName) strip(jobStatus)

  json = '{"message":"'    || EscapeJson(strip(msg))       || '"'
  json = json || ',"level":"INFO"'
  json = json || ',"source":"'     || EscapeJson(Source)    || '"'
  json = json || ',"jobName":"'    || EscapeJson(strip(jobName))   || '"'
  json = json || ',"jobStatus":"'  || strip(jobStatus)     || '"'
  json = json || ',"computerName":"' || GetHostName()      || '"'
  json = json || '}'

  call PostToApi json
  return


/*───────────────────────────────────────────────────────────────────────*/
/* PostToApi: HTTP POST the JSON payload via curl                        */
/*───────────────────────────────────────────────────────────────────────*/
PostToApi: procedure expose BaseUrl
  parse arg payload

  endpoint = BaseUrl || "/api/Logs/ingest"

  /* Build curl command — silent, discard output */
  cmd = 'curl.exe -s -o nul -X POST "' || endpoint || '"' ,
        '-H "Content-Type: application/json"' ,
        '-d "' || payload || '"'

  /* Execute (fire and forget) */
  cmd
  rc = rc

  if rc \= 0 then
    say "LOG-INGEST WARNING: curl returned" rc

  return


/*───────────────────────────────────────────────────────────────────────*/
/* EscapeJson: Escape double quotes and backslashes for JSON strings     */
/*───────────────────────────────────────────────────────────────────────*/
EscapeJson: procedure
  parse arg text
  text = ChangeStr('\', text, '\\')
  text = ChangeStr('"', text, '\"')
  return text


/*───────────────────────────────────────────────────────────────────────*/
/* GetHostName: Return the computer name from environment                */
/*───────────────────────────────────────────────────────────────────────*/
GetHostName: procedure
  return value("COMPUTERNAME",, "ENVIRONMENT")
