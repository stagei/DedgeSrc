      ******************************************************************
      * LOGINGEST.CBL — Send a log entry to GenericLogHandler
      *
      * Calls curl.exe via SYSTEM to POST JSON to the ingest API.
      * This is a fire-and-forget pattern — the program does not
      * wait for queue processing, only for the HTTP 202 response.
      *
      * Requirements:
      *   - curl.exe on PATH (included in Windows 10+/Server 2019+)
      *   - Network access to the GenericLogHandler server
      *
      * Usage:
      *   MOVE "Order 12345 processed" TO WS-MESSAGE
      *   MOVE "INFO"                  TO WS-LEVEL
      *   MOVE "COBNT-OrderProc"       TO WS-SOURCE
      *   PERFORM SEND-LOG-ENTRY
      *
      * For job tracking:
      *   MOVE "NightlyBatch"  TO WS-JOB-NAME
      *   MOVE "Started"       TO WS-JOB-STATUS
      *   PERFORM SEND-LOG-ENTRY
      ******************************************************************

       IDENTIFICATION DIVISION.
       PROGRAM-ID. LOGINGEST.

       DATA DIVISION.
       WORKING-STORAGE SECTION.

      * ── Configuration ──────────────────────────────────────
       01  WS-BASE-URL        PIC X(80) VALUE
           "http://dedge-server/GenericLogHandler".
       01  WS-ENDPOINT        PIC X(120) VALUE SPACES.

      * ── Input fields (set these before PERFORM SEND-LOG-ENTRY)
       01  WS-MESSAGE         PIC X(500) VALUE SPACES.
       01  WS-LEVEL           PIC X(10)  VALUE "INFO".
       01  WS-SOURCE          PIC X(50)  VALUE "COBOL-PROGRAM".
       01  WS-COMPUTER-NAME   PIC X(50)  VALUE SPACES.
       01  WS-JOB-NAME        PIC X(100) VALUE SPACES.
       01  WS-JOB-STATUS      PIC X(20)  VALUE SPACES.
       01  WS-ERROR-ID        PIC X(50)  VALUE SPACES.

      * ── Work fields ────────────────────────────────────────
       01  WS-JSON-PAYLOAD    PIC X(2000) VALUE SPACES.
       01  WS-CURL-CMD        PIC X(3000) VALUE SPACES.
       01  WS-RETURN-CODE     PIC S9(4) COMP VALUE 0.

       PROCEDURE DIVISION.

       MAIN-LOGIC.
      * Example: send an INFO log on program start
           MOVE "LOGINGEST sample program started"
               TO WS-MESSAGE
           MOVE "INFO"              TO WS-LEVEL
           MOVE "LOGINGEST-Sample"  TO WS-SOURCE
           MOVE "SampleJob"         TO WS-JOB-NAME
           MOVE "Started"           TO WS-JOB-STATUS
           PERFORM SEND-LOG-ENTRY

      * Example: send an ERROR log
           MOVE "Database connection failed on retry 3"
               TO WS-MESSAGE
           MOVE "ERROR"             TO WS-LEVEL
           MOVE "DB-CONN-003"       TO WS-ERROR-ID
           MOVE SPACES              TO WS-JOB-STATUS
           PERFORM SEND-LOG-ENTRY

      * Example: send job completion
           MOVE "SampleJob completed - 150 records"
               TO WS-MESSAGE
           MOVE "INFO"              TO WS-LEVEL
           MOVE SPACES              TO WS-ERROR-ID
           MOVE "Completed"         TO WS-JOB-STATUS
           PERFORM SEND-LOG-ENTRY

           STOP RUN.

      ******************************************************************
      * SEND-LOG-ENTRY — Build JSON and POST via curl
      ******************************************************************
       SEND-LOG-ENTRY.
           STRING WS-BASE-URL DELIMITED SPACES
                  "/api/Logs/ingest" DELIMITED SIZE
                  INTO WS-ENDPOINT
           END-STRING

      * Build the JSON payload
           PERFORM BUILD-JSON

      * Build the curl command
      * -s = silent, -o nul = discard body, -w = show status
           STRING
               'curl.exe -s -o nul -X POST "'
                   DELIMITED SIZE
               WS-ENDPOINT DELIMITED SPACES
               '" -H "Content-Type: application/json" -d "'
                   DELIMITED SIZE
               WS-JSON-PAYLOAD DELIMITED "  "
               '"' DELIMITED SIZE
               INTO WS-CURL-CMD
           END-STRING

      * Execute curl (fire-and-forget)
           CALL "SYSTEM" USING WS-CURL-CMD
               RETURNING WS-RETURN-CODE
           END-CALL

           IF WS-RETURN-CODE NOT = 0
               DISPLAY "LOG-INGEST WARNING: curl returned "
                   WS-RETURN-CODE
           END-IF

      * Reset optional fields for next call
           MOVE SPACES TO WS-JOB-NAME
           MOVE SPACES TO WS-JOB-STATUS
           MOVE SPACES TO WS-ERROR-ID
           MOVE SPACES TO WS-JSON-PAYLOAD
           MOVE SPACES TO WS-CURL-CMD
           MOVE SPACES TO WS-ENDPOINT.

      ******************************************************************
      * BUILD-JSON — Construct the JSON string
      ******************************************************************
       BUILD-JSON.
           MOVE SPACES TO WS-JSON-PAYLOAD

           STRING
               '{"message":"' DELIMITED SIZE
               WS-MESSAGE DELIMITED "  "
               '","level":"' DELIMITED SIZE
               WS-LEVEL DELIMITED SPACES
               '","source":"' DELIMITED SIZE
               WS-SOURCE DELIMITED "  "
               '"' DELIMITED SIZE
               INTO WS-JSON-PAYLOAD
           END-STRING

      * Append jobName if set
           IF WS-JOB-NAME NOT = SPACES
               INSPECT WS-JSON-PAYLOAD
                   REPLACING TRAILING SPACES BY LOW-VALUES
               STRING WS-JSON-PAYLOAD DELIMITED LOW-VALUES
                      ',"jobName":"' DELIMITED SIZE
                      WS-JOB-NAME DELIMITED "  "
                      '"' DELIMITED SIZE
                      INTO WS-JSON-PAYLOAD
               END-STRING
           END-IF

      * Append jobStatus if set
           IF WS-JOB-STATUS NOT = SPACES
               INSPECT WS-JSON-PAYLOAD
                   REPLACING TRAILING SPACES BY LOW-VALUES
               STRING WS-JSON-PAYLOAD DELIMITED LOW-VALUES
                      ',"jobStatus":"' DELIMITED SIZE
                      WS-JOB-STATUS DELIMITED "  "
                      '"' DELIMITED SIZE
                      INTO WS-JSON-PAYLOAD
               END-STRING
           END-IF

      * Append errorId if set
           IF WS-ERROR-ID NOT = SPACES
               INSPECT WS-JSON-PAYLOAD
                   REPLACING TRAILING SPACES BY LOW-VALUES
               STRING WS-JSON-PAYLOAD DELIMITED LOW-VALUES
                      ',"errorId":"' DELIMITED SIZE
                      WS-ERROR-ID DELIMITED "  "
                      '"' DELIMITED SIZE
                      INTO WS-JSON-PAYLOAD
               END-STRING
           END-IF

      * Close the JSON object
           INSPECT WS-JSON-PAYLOAD
               REPLACING TRAILING SPACES BY LOW-VALUES
           STRING WS-JSON-PAYLOAD DELIMITED LOW-VALUES
                  "}" DELIMITED SIZE
                  INTO WS-JSON-PAYLOAD
           END-STRING.
