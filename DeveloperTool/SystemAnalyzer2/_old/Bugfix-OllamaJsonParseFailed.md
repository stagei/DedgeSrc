# Bugfix: Ollama JSON Parse Failed for Variable Filename Resolution

**Status:** Open
**Component:** `Invoke-FullAnalysis.ps1` — Phase 3 CALL expansion, variable filename resolution via Ollama
**Severity:** Low (non-blocking warnings, pipeline continues)
**Date logged:** 2026-03-28

## Symptom

During Phase 3 CALL expansion, Ollama is asked to resolve COBOL variable-based filenames to physical paths. The response is expected to be valid JSON with a `basePath` property, but Ollama frequently returns non-JSON text, causing `ConvertFrom-Json` to fail.

The warnings appear for many programs with file I/O variables, especially programs with many SELECT ASSIGN targets.

## Sample Errors

```
WARNING:   Ollama JSON parse failed for BIVINNK/PRTFILE: Conversion from JSON failed with error: Unexpected character encountered while parsing value: F. Path 'basePath', line 1, position 12.
WARNING:   Ollama JSON parse failed for BIVINNK/ANALYCEN: Conversion from JSON failed with error: Unexpected character encountered while parsing value: B. Path 'basePath', line 1, position 12.
WARNING:   Ollama JSON parse failed for BIVINNK/BINIR: Conversion from JSON failed with error: Unexpected character encountered while parsing value: T. Path 'basePath', line 1, position 12.
WARNING:   Ollama JSON parse failed for BIVINNK/PREDIKTOR: Conversion from JSON failed with error: Unexpected character encountered while parsing value: F. Path 'basePath', line 1, position 12.
WARNING:   Ollama JSON parse failed for BIVINNK/PREDIKTOR2: Conversion from JSON failed with error: Unexpected character encountered while parsing value: #. Path 'basePath', line 1, position 12.
WARNING:   Ollama JSON parse failed for BIVINNK/OPTILON: Conversion from JSON failed with error: Unexpected character encountered while parsing value: T. Path 'basePath', line 1, position 12.
WARNING:   Ollama JSON parse failed for BIVINNK/MARKED: Conversion from JSON failed with error: Unexpected character encountered while parsing value: B. Path 'basePath', line 1, position 12.
WARNING:   Ollama JSON parse failed for BIVINNK/FULLMAKT: Conversion from JSON failed with error: Unexpected character encountered while parsing value: A. Path 'basePath', line 1, position 12.
WARNING:   Ollama JSON parse failed for BIVINNK/MOTTAKER: Conversion from JSON failed with error: Unexpected character encountered while parsing value: B. Path 'basePath', line 1, position 12.
WARNING:   Ollama JSON parse failed for BIVINNK/VALUTA: Conversion from JSON failed with error: Unexpected character encountered while parsing value: c. Path 'basePath', line 1, position 12.
```

Additional patterns observed:

```
WARNING:   Ollama JSON parse failed for D01B998/VERS-FIL: ...After parsing a value an unexpected character was encountered: :. Path 'code[0].variables[11]', line 1, position 890.
WARNING:   Ollama JSON parse failed for D01B998/PREDIKTOR2: ...Additional text encountered after finished reading JSON content: {. Path '', line 3, position 0.
WARNING: Ollama error: The request was canceled due to the configured HttpClient.Timeout of 120 seconds elapsing.
```

## Root Cause Analysis

Ollama (`qwen2.5:7b` / `qwen3:8b`) is prompted to return a JSON object like `{"basePath": "/some/path", ...}` but instead returns:

1. **Free-text explanations** starting with words like "Based on...", "The file...", etc. — the parser hits a letter at position 12 of `basePath` value
2. **Malformed JSON** with extra braces, trailing content, or nested objects where strings are expected
3. **Timeouts** (120s) when the model takes too long to generate a response

The prompt asks Ollama to resolve a COBOL variable filename (e.g., `WW-PRTFILE`) to a physical file path, but the model often narrates instead of producing strict JSON.

## Potential Fixes

1. **Stricter prompt engineering** — Add `Respond ONLY with JSON, no explanation` and use JSON mode if the Ollama model supports it (`"format": "json"` in the API request)
2. **Response post-processing** — Extract JSON from the response using regex `\{[^}]+\}` before parsing, to handle cases where Ollama wraps JSON in explanation text
3. **Retry with temperature=0** — Lower temperature for more deterministic/structured output
4. **Fallback to regex extraction** — If JSON parse fails, try to extract `basePath` value via pattern matching
5. **Batch requests** — Instead of one Ollama call per variable, batch all variables for a program into a single prompt to reduce timeout risk

## Impact

- Pipeline continues without resolved file paths (graceful degradation)
- `all_file_io.json` entries for affected programs will have empty `resolvedPath`, `filenamePattern`, and `filenameDescription` fields
- No data loss — the logical file name and COBOL assignment are still captured
