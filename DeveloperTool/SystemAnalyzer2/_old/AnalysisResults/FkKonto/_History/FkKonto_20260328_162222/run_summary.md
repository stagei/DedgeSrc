# Pipeline Run Summary

Generated: 2026-03-28 16:22:37
Run folder: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\SystemAnalyzer\AnalysisResults\FkKonto\_History\FkKonto_20260328_162222`
Database: **FKKONTO** (alias: FKKONTO)

## Main Statistics

| Metric | Value |
|---|---:|
| Programs in dependency master | 32 |
| Total programs (all included) | 32 |
| SQL references | 101 |
| Unique SQL tables | 33 |
| Unique COPY elements | 61 |
| Call graph edges | 53 |
| File I/O references | 23 |
| Unique files | 12 |
| Program source found (real %) | 100 |
| COPY found (%) | 21.3 |
| DB2 validated tables | 30 / 30 |
| Database boundary | FKKONTO (139 qualifiedNames) |
| Programs rejected (foreign tables) | 0 |
| SQL ops stripped (non-matching) | 26 |
| Deprecated (UTGATT) | 3 |

## Program Discovery Breakdown

| Source | Count |
|---|---:|
| Original | 10 |
| CALL expansion | 16 |
| Table reference | 6 |
| Local source | 32 |
| RAG | 0 |

### CBL/CPY Folder Coverage

| Folder | Expected | Found | Missing |
|---|---:|---:|---:|
| CBL folder (exact + U/V fuzzy) | 32 | 32 | 0 |
| CPY folder (copy elements) | 61 | 13 | 48 |

## Source Verification

| Status | Count |
|---|---:|
| CBL exact | 32 |
| Uncertain folder match | 0 |
| U/V fuzzy match | 0 |
| Other type found | 0 |
| Noise filtered | 0 |
| Truly missing | 0 |

