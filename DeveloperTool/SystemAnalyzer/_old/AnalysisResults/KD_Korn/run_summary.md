# Pipeline Run Summary

Generated: 2026-03-28 16:26:04
Run folder: `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\data\SystemAnalyzer\AnalysisResults\KD_Korn\_History\KD_Korn_20260328_162257`
Database: **BASISRAP** (alias: BASISRAP)

## Main Statistics

| Metric | Value |
|---|---:|
| Programs in dependency master | 351 |
| Total programs (all included) | 351 |
| SQL references | 3398 |
| Unique SQL tables | 651 |
| Unique COPY elements | 1161 |
| Call graph edges | 786 |
| File I/O references | 239 |
| Unique files | 113 |
| Program source found (real %) | 97.7 |
| COPY found (%) | 29.8 |
| DB2 validated tables | 164 / 164 |
| Database boundary | BASISRAP (3486 qualifiedNames) |
| Programs rejected (foreign tables) | 0 |
| SQL ops stripped (non-matching) | 285 |

## Program Discovery Breakdown

| Source | Count |
|---|---:|
| Original | 99 |
| CALL expansion | 84 |
| Table reference | 168 |
| Local source | 343 |
| RAG | 8 |

### CBL/CPY Folder Coverage

| Folder | Expected | Found | Missing |
|---|---:|---:|---:|
| CBL folder (exact + U/V fuzzy) | 351 | 342 | 9 |
| CPY folder (copy elements) | 1161 | 346 | 815 |

## Source Verification

| Status | Count |
|---|---:|
| CBL exact | 321 |
| Uncertain folder match | 0 |
| U/V fuzzy match | 21 |
| Other type found | 1 |
| Noise filtered | 0 |
| Truly missing | 8 |

