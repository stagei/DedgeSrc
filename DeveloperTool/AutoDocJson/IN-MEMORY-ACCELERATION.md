# AutoDocJson - In-Memory Acceleration Options

## Problem Statement

AutoDocJson spends significant time on repeated disk I/O during parsing. The main bottleneck is `FindAutodocUsages()` in `ParserBase.cs`, which is called **for every single file parsed** to find execution paths (who calls what). Each call:

1. Enumerates all `*.ps1`, `*.bat`, `*.rex`, `*.cbl` files recursively across the entire repo tree
2. Reads every matching file with `File.ReadAllLines()`
3. Scans each line for the search pattern
4. This happens **twice per file** (primary + secondary search, two levels deep)

For 180 files (30 per type), this means ~360 full scans of ~10,000 source files = **~3.6 million file reads** from disk.

---

## Current Data Profile

| Category | Files | Size |
|----------|------:|-----:|
| **Total repos (with .git, bin, etc.)** | 115,520 | 2,926 MB (2.86 GB) |
| **Source files only (no .git/bin/obj)** | 14,030 | 362 MB |
| **Files scanned by FindAutodocUsages** | 9,966 | 210 MB |
| **Cobdok CSV metadata** | 21 | 29 MB |
| **Total working dataset** | ~10,000 | **~240 MB** |

### Source Files by Extension

| Extension | Files | Size (MB) |
|-----------|------:|----------:|
| .cbl | 3,695 | 180.1 |
| .gs | 1,223 | 64.8 |
| .imp | 1,194 | 47.7 |
| .json | 430 | 29.6 |
| .ps1 | 2,585 | 11.4 |
| .rex | 914 | 9.0 |
| .bat | 2,513 | 8.4 |
| .cs | 869 | 6.8 |
| .psm1 | 39 | 3.0 |
| .xml | 259 | 1.0 |

### Top Repositories by Size

| Repository | Size (MB) | Files |
|------------|----------:|------:|
| ForsprangBatch | 1,663 | 7,071 |
| DedgePsh | 445 | 5,545 |
| Dedge | 339 | 13,764 |
| DedgeNodeJs | 257 | 5,433 |
| Databases | 52 | 80,413 |
| ServerMonitor | 42 | 301 |

---

## Options Evaluated

### Option 1: ConcurrentDictionary File Cache (RECOMMENDED)

**Approach**: At startup, preload all searchable source files into a `ConcurrentDictionary<string, string[]>` keyed by file path. Replace all `File.ReadAllLines()` calls in `FindAutodocUsages()` with dictionary lookups.

**Memory cost**: ~240 MB (the entire searchable dataset)

**Implementation**:
```csharp
public class SourceFileCache
{
    private readonly ConcurrentDictionary<string, string[]> _cache = new();
    private readonly ConcurrentDictionary<string, string> _fileIndex = new(); // lowercase filename -> full path

    public void PreloadAll(string rootFolder, string[] extensions)
    {
        var files = Directory.EnumerateFiles(rootFolder, "*.*", SearchOption.AllDirectories)
            .Where(f => extensions.Any(e => f.EndsWith(e, StringComparison.OrdinalIgnoreCase))
                && !f.Contains("\\.git\\") && !f.Contains("\\bin\\") && !f.Contains("\\obj\\"));

        Parallel.ForEach(files, file =>
        {
            var lines = File.ReadAllLines(file, Encoding.GetEncoding(1252));
            _cache.TryAdd(file, lines);
            _fileIndex.TryAdd(Path.GetFileName(file).ToLower(), file);
        });
    }

    public string[]? GetLines(string filePath) =>
        _cache.TryGetValue(filePath, out var lines) ? lines : null;

    public IEnumerable<(string Path, string[] Lines)> GetFilesByExtension(string extension) =>
        _cache.Where(kvp => kvp.Key.EndsWith(extension, StringComparison.OrdinalIgnoreCase))
              .Select(kvp => (kvp.Key, kvp.Value));
}
```

| Pros | Cons |
|------|------|
| Simplest to implement (~50 lines) | Uses ~240 MB RAM |
| Zero external dependencies | Files loaded at startup (one-time cost ~5-10s) |
| Drop-in replacement for existing code | Cache invalidation needed if files change mid-run |
| Thread-safe out of the box | |
| Eliminates ~3.6M redundant file reads | |

**Estimated speedup**: 3-5x for the execution path scanning phase. The ~210 MB of searchable files are read once instead of thousands of times.

**Effort**: Low (1-2 hours). Modify `ParserBase.FindAutodocUsages()` and `ExecutionPathHelper` to use the cache.

---

### Option 2: LIFTI - In-Memory Full-Text Search Index

**Approach**: Use the LIFTI NuGet package to build an in-memory inverted index of all source files. Search becomes O(1) lookups instead of linear scans.

**NuGet**: `Lifti.Core`

**How it works**: LIFTI tokenizes text and builds an inverted index (word -> list of documents containing it). Searching for "AABELMA" would instantly return all files containing that token.

```csharp
var index = new FullTextIndexBuilder<string>()
    .WithDefaultTokenization(o => o.CaseInsensitive())
    .Build();

// Index all files
foreach (var file in sourceFiles)
    await index.AddAsync(file.Path, File.ReadAllText(file.Path));

// Search is instant
var results = index.Search("AABELMA");
```

| Pros | Cons |
|------|------|
| Sub-millisecond searches | Requires NuGet dependency |
| Handles fuzzy matching | Index build time (~30s for 210 MB) |
| Purpose-built for text search | May not support line-level context needed by AutoDoc |
| Memory-efficient inverted index | Significant refactoring of FindAutodocUsages |

**Estimated speedup**: 10-50x for search operations. But requires the most code changes.

**Effort**: Medium (4-8 hours). Need to adapt all search callers to use LIFTI query API.

---

### Option 3: Lucene.NET - Full-Text Search Engine

**Approach**: Use Apache Lucene.NET to build a searchable index. Supports in-memory `RAMDirectory` storage.

**NuGet**: `Lucene.Net` (v4.8-beta)

```csharp
using var dir = new RAMDirectory();
using var analyzer = new StandardAnalyzer(LuceneVersion.LUCENE_48);
var config = new IndexWriterConfig(LuceneVersion.LUCENE_48, analyzer);
using var writer = new IndexWriter(dir, config);

// Index files
foreach (var file in sourceFiles)
{
    var doc = new Document();
    doc.Add(new StringField("path", file, Field.Store.YES));
    doc.Add(new TextField("content", File.ReadAllText(file), Field.Store.NO));
    writer.AddDocument(doc);
}
```

| Pros | Cons |
|------|------|
| Industry-standard search engine | Heavy dependency (large library) |
| Extremely fast search | Complex API |
| Supports advanced queries | Overkill for pattern matching |
| Battle-tested at massive scale | Index build time |

**Estimated speedup**: 10-100x for search. But massive overkill for this use case.

**Effort**: High (8-16 hours). Significant API surface to learn and integrate.

---

### Option 4: Memory-Mapped Files

**Approach**: Use `MemoryMappedFile` to map source files into virtual memory, letting the OS page them in/out.

| Pros | Cons |
|------|------|
| OS-managed caching | No faster than ReadAllLines for sequential reads |
| Low memory pressure | Complex API for line-by-line processing |
| Good for random access | Benchmarks show it's actually slower than FileStream |

**Estimated speedup**: 0-20%. Not recommended - benchmarks show `File.ReadAllLines` is already faster for sequential reading.

**Effort**: Medium. Not worth the complexity for minimal gain.

---

### Option 5: Pre-computed Search Index (Custom)

**Approach**: At startup, build a `Dictionary<string, List<string>>` mapping each unique token/filename to the list of files containing it. This is essentially a manual inverted index.

```csharp
// Key: lowercase search term (e.g., "aabelma")
// Value: list of file paths containing that term
var searchIndex = new Dictionary<string, HashSet<string>>();

foreach (var file in sourceFiles)
{
    var baseName = Path.GetFileNameWithoutExtension(file).ToLower();
    foreach (var line in File.ReadAllLines(file))
    {
        // Extract potential program references from each line
        // Add to index: token -> file
    }
}
```

| Pros | Cons |
|------|------|
| O(1) lookup per search | Complex to build correctly |
| No external dependencies | Must match exact FindAutodocUsages logic |
| Minimal memory (just paths, not content) | Harder to maintain |

**Estimated speedup**: 20-100x. But requires careful implementation to match existing search semantics.

**Effort**: Medium-High (4-8 hours).

---

## Recommendation

### Phase 1: ConcurrentDictionary Cache (Do First)

**Why**: Lowest effort, highest certainty, zero dependencies. The working dataset is only 240 MB which fits comfortably in memory on any modern machine. The 28-core server this runs on has plenty of RAM.

**What changes**:
1. Create `SourceFileCache` class in `AutoDocJson.Core`
2. Preload all source files at startup (after git clone, before parsing)
3. Modify `ParserBase.FindAutodocUsages()` to read from cache instead of disk
4. Modify individual parsers' `File.ReadAllLines()` calls for source files to use cache
5. Preload cobdok CSV files into cache as well

**Expected result**: Eliminate ~3.6 million redundant file reads per 180-file run. The execution path scanning phase should drop from minutes to seconds.

### Phase 2: Pre-computed Inverted Index (Optional Future)

If Phase 1 isn't fast enough, build a lightweight inverted index at startup that maps `filename -> list of files referencing it`. This would make `FindAutodocUsages()` O(1) per lookup instead of O(n) scanning.

### Not Recommended

- **Lucene.NET**: Overkill. We're doing simple substring matching, not full-text search with ranking.
- **Memory-Mapped Files**: Benchmarks show no benefit over `ReadAllLines` for sequential access.
- **RAM Disk**: Excluded per user requirement. Also, the OS file cache already provides similar benefits for repeated reads.

---

## Implementation Priority

| Phase | Option | Effort | Speedup | RAM Cost |
|-------|--------|--------|---------|----------|
| **1** | ConcurrentDictionary Cache | 1-2 hours | 3-5x | ~240 MB |
| **2** | Pre-computed Inverted Index | 4-8 hours | 20-100x | ~50 MB |
| 3 | LIFTI Full-Text Index | 4-8 hours | 10-50x | ~100 MB |
| - | Lucene.NET | 8-16 hours | Not needed | ~200 MB |
| - | Memory-Mapped Files | 4-6 hours | ~0% | OS managed |
