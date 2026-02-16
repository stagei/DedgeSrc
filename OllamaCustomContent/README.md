# Adding Your Own Content to Local Ollama Models

You have a large set of markdown documents (from PDF, HTML, CAB, or other exports—e.g. from **VcHelpExport** or **Doc2Markdown** in this repo) that no public or hosted AI is trained on. This guide answers two questions and gives a practical path forward.

## What You Can Do With It

The aim is to **run queries over your own content** using a local LLM—for example over **all content under a folder** such as `c:\opt\src`—to find **links, similarities, references, and relationships** that only exist in your codebase and docs. You index that folder (and any subfolders) into a RAG “database,” then ask questions in natural language; the model uses the retrieved chunks as context to answer. One sample of the kind of thing you can do:

- *“Which COBOL programs insert data into table `CUSTOMER`?”* (code ↔ table links)
- *“What files reference this API / this config key?”*
- *“What docs or code are similar to this paragraph?”*
- *“Where is `X` defined and where is it used?”*

So: index a broad tree (e.g. `c:\opt\src`), then use the LLM to query it for links and similarities—no cloud, no sending your content out. The rest of this doc explains how (RAG with Ollama) and what file types you can include.

---

## Can I Use Cursor’s Index or “Add Folders as Indexed Docs”?

**Yes.** You don’t add a separate “RAG” to Cursor—Cursor already does **codebase indexing** (semantic search over your files and feeding that as context to the AI). You just need the right **workspace** so that your folder is part of what gets indexed.

- **Single folder as workspace**  
  Open the folder you care about (e.g. `c:\opt\src`) as the Cursor workspace (File → Open Folder). Cursor indexes that folder and its subfolders. In chat you can use **@codebase** (or the codebase context) so the model can search and reason over that content. Same idea as RAG: index → semantic search → context for the LLM.

- **Multiple folders (“indexed docs”)**  
  To include several trees (e.g. `c:\opt\src` plus another repo), use a **multi-root workspace**: create a `.code-workspace` file that lists all the roots, then open that workspace in Cursor. All listed folders are indexed together, so the AI can query across them.

- **Controlling what’s indexed**  
  Use a **`.cursorignore`** file (similar to `.gitignore`) to exclude paths you don’t want in the index.

So: **you can “add the folders as indexed docs” by opening them as your workspace (or as roots in a .code-workspace).** No extra RAG setup inside Cursor. The model Cursor uses (cloud or local, depending on your settings) will then have access to that indexed content for links, similarities, and references.

**When to use Cursor’s index vs your own RAG (e.g. Ollama):**

| Use Cursor’s indexing when… | Use your own RAG (Ollama + vector store) when… |
|-----------------------------|-----------------------------------------------|
| You want to query from inside Cursor chat/editor. | You want a standalone, scriptable “query my docs” pipeline. |
| You’re fine with Cursor’s AI (cloud or local model in Cursor). | You want 100% local, only Ollama, no Cursor dependency. |
| One place = workspace + index + chat. | You want to reuse the same index from scripts, other UIs, or APIs. |

Both give you “query this folder for links and similarities”; Cursor does it built-in for the workspace you open, your own RAG does it with a pipeline you control (e.g. Ollama + Chroma).

### Running Cursor queries from the command line and getting Markdown back

**Yes.** Cursor has a **headless CLI** so you can run the same kind of codebase-aware query from a script or terminal and capture the answer.

- **Install / use the CLI**  
  The Cursor CLI is part of Cursor (or installable separately). From a terminal, run the `cursor` command from the **workspace directory** (e.g. `c:\opt\src`) so the agent has access to the indexed codebase.

- **Print mode (non-interactive)**  
  Use **`-p`** or **`--print`** so the run is non-interactive and the model's reply is printed to stdout (no chat UI).

- **Getting Markdown back**  
  The CLI offers **`--output-format`** with values like `text`, `json`, or `stream-json`. There is no separate "markdown" format: the model's reply is just text. To get Markdown:
  - Ask for it in the prompt (e.g. *"Answer in Markdown only, with headers and lists."*), and/or  
  - Capture stdout and save it to a `.md` file.

**Example (PowerShell, run from your workspace root, e.g. `c:\opt\src`):**

```powershell
# From the folder you use as Cursor workspace (so codebase is indexed)
cd C:\opt\src
cursor agent -p "List all COBOL programs that insert into table CUSTOMER. Answer in Markdown with a bullet list and file paths." > result.md
```

**Example with JSON output** (if you want to parse the response programmatically):

```powershell
cursor agent -p --output-format json "Which files reference the CUSTOMER table? Return a short Markdown summary." | Out-File -Encoding utf8 result.json
```

Check Cursor's CLI docs for your version (**Cursor → Docs → CLI / Headless**) for exact flags (`--model`, `--mode ask` vs `agent`, etc.). Summary: **you can execute Cursor-style codebase queries from the command line and get back text (including Markdown) by using `cursor agent -p "your question"` from the workspace directory and redirecting stdout to a `.md` file.**

---

## Can I Train an AI on My Content and Rebuild the Model?

**Short answer:** You can *fine-tune* or *continue-training* a base model on your content, but **Ollama itself does not train or rebuild models**. Ollama runs pre-built models (e.g. Llama, Mistral, Qwen) that you pull and use as-is.

- **Fine-tuning** means taking an existing model and updating its weights on your dataset. That requires:
  - The base model weights and tooling (e.g. Hugging Face Transformers, Unsloth, or framework-specific kits).
  - A prepared dataset (often Q&A or instruction-style from your docs).
  - Significant compute (GPU, memory, time).
  - Exporting the result to a format Ollama can run (e.g. GGUF), then loading it in Ollama as a *new* custom model.

- **When it makes sense:** When you need the model to *internally* “know” your domain (e.g. specific terminology, patterns, or style) and you’re willing to invest in data prep and training. The model is then fixed until you train again.

- **When it doesn’t:** When you mainly want to *query* your documents (search + answer). For that, you don’t need to retrain; you use your docs as an external knowledge base (see below).

---

## Can I Add Documents as an Additional “Database” for Ollama?

**Yes.** This is the standard approach: keep the Ollama model unchanged and use your markdown (or any text) as a **retrievable knowledge base**. The technique is called **RAG (Retrieval-Augmented Generation)**.

- Your documents are **not** baked into the model.
- They live in a **vector store** (or similar): chunks of text are turned into **embeddings** (vectors), and at query time you find the most relevant chunks and pass them to the model as **context** in the prompt.
- Ollama can provide both:
  - **Embeddings** (to build the document index), and  
  - **Chat/completion** (to answer questions using that context).

So: you *add* your content as a queryable “database” that the model reads at answer time; you do *not* have to rebuild the model.

---

## What File Types Can I Use?

**Any text-based files.** RAG works on the *text* you feed it. When you index a folder (e.g. `c:\opt\src` and subfolders), you can include and mix:

- **Markdown** (e.g. from VcHelpExport, Doc2Markdown)
- **COBOL source** (`.cbl`, `.cob`, etc.)
- **SQL** (DDL like `CREATE TABLE`, scripts, views)
- **Other code** (C#, PowerShell, JS, etc.)
- **Config files, logs, CSV, JSON, XML** – anything you can read as plain text

Index them all in the **same vector store** (or separate collections by type if you prefer). Then you run the same kind of query over the whole set: find links, references, and similarities. The COBOL/SQL case below is just **one sample**; you can ask things like:

- *“Which COBOL programs insert data into table `CUSTOMER`?”*
- *“What tables are defined in our DDL and which programs reference them?”*
- *“Where is `WS-ORDER-ID` used?"* and *"What in this folder is similar to this snippet?"* or *"What references this path or symbol?"*”*

The model will only “see” what you put in the index. If your chunks contain the relevant `INSERT INTO CUSTOMER` (or similar) and you **store the source filename as metadata** on each chunk, retrieval can return both the code snippet and the file it came from. You (or the LLM) can then list the distinct files that match.

### Making “which files do X?” work well

1. **Store source identity on every chunk**  
   When you chunk a file, attach metadata such as `file_path`, `file_name`, and optionally `file_type` (e.g. `cobol`, `sql`). After retrieval, you can aggregate by file and answer “these COBOL files insert into table X.”

2. **Chunk size**  
   For code, chunk by procedure/paragraph or by a few statements so that `INSERT INTO tablename` and the program name (or path) appear together in the same chunk or in nearby chunks.

3. **Optional: hybrid search**  
   For very precise “list all files that INSERT into table T,” you can combine:
   - **Keyword/search** (e.g. grep for `INSERT` and the table name) to get candidate files or chunks, and  
   - **RAG** to rank, explain, or summarize. Some vector stores support hybrid (vector + keyword) search.

So yes: you can use COBOL sources, SQL DDL, and any other text files, and query things like “which COBOL files are inserting data into table &lt;tablename&gt;?” as long as that information is present in the indexed text and you keep filename/source in metadata.

---

## RAG in Practice: Using Your Documents with Ollama

### High-level steps

1. **Chunk your markdown**  
   Split each document into overlapping or non-overlapping segments (e.g. by paragraph, section, or fixed token size). Smaller chunks (e.g. 256–512 tokens) often give more precise retrieval.

2. **Embed chunks with Ollama**  
   Use an **embedding model** in Ollama (e.g. `nomic-embed-text`) to turn each chunk into a vector. No cloud API required.

3. **Store vectors**  
   Put the vectors (and the original text) in a **vector store**: Chroma, LanceDB, Qdrant, or even a simple in-memory index. This is your “document database.”

4. **At query time**  
   - Embed the user question with the same Ollama embedding model.  
   - Retrieve the top‑k most similar chunks from the vector store.  
   - Build a prompt: e.g. “Use only the following context to answer. Context: … Question: …”  
   - Send that prompt to an Ollama **chat model** (e.g. Llama, Mistral).  
   - Return the model’s answer.

All of this can run locally: Ollama for embeddings + LLM, your markdown as the only “training” data in the form of a searchable index.

### What you need

- **Ollama** installed and running (e.g. `ollama serve`).
- An **embedding model** in Ollama, e.g.  
  `ollama pull nomic-embed-text`  
  (or `mxbai-embed-large`; check [Ollama library](https://ollama.com/library) for current names.)
- A **chat model** for answers, e.g.  
  `ollama pull llama3.2`  
  (or any model you already use.)
- A **vector store** and a small script or app that:
  - Reads your documents (markdown, COBOL, SQL, or any text files),
  - Chunks them and attaches metadata (e.g. `file_path`, `file_type`),
  - Calls Ollama’s embedding API for each chunk,
  - Stores vectors + text + metadata,
  - Implements “embed query → search → build prompt → call Ollama chat.”

### Ollama embedding API (example)

```bash
# One chunk at a time
curl http://localhost:11434/api/embeddings -d '{
  "model": "nomic-embed-text",
  "prompt": "Your markdown chunk or user question here"
}'
```

Use the same `model` for both indexing your docs and embedding the user’s question so that similarity search is meaningful.

---

## Options and Tools (All Local)

- **Chroma** – Simple vector DB; supports an Ollama embedding function (point it at `http://localhost:11434/api/embeddings`).
- **LanceDB** – Embedding APIs that can use Ollama.
- **LangChain / LlamaIndex** – Use Ollama as the embedding and LLM provider, and their document loaders/splitters to ingest markdown, code, and other text and build a RAG pipeline.
- **Dedicated UIs** – e.g. [ollama-local-rag](https://github.com/cpepper96/ollama-local-rag), [OllamaRAG](https://github.com/shalvamist/ollamarag) (Chroma + Streamlit); you can point them at a folder of markdown files.

You can also write a minimal pipeline yourself (e.g. in Python or PowerShell): read your files (`.md`, `.cbl`, `.sql`, etc.) → split into chunks (with filename metadata) → call Ollama embeddings → store in your chosen vector DB → on query: embed → retrieve → prompt Ollama chat.

---

## Summary

| Goal | Approach | With Ollama? |
|------|----------|--------------|
| Model “knows” your content by default (training) | Fine-tune / continue-train a base model, then run the new model in Ollama | Ollama runs the model; training is done elsewhere, then you import the new GGUF (or supported format). |
| Use your docs as a queryable knowledge base | RAG: embed docs → vector store → retrieve + prompt at query time | Yes: use Ollama for embeddings and for chat; your markdown is the “database” you add. |

**Recommendation:** For a large set of markdown that no model is trained on, **use RAG**: add your content as a document database (vector store) and keep using standard Ollama models. Only consider fine-tuning if you need the model’s internal behavior to change in a way RAG cannot provide.

---

## References

- [Ollama API](https://github.com/ollama/ollama/blob/main/docs/api.md) – chat and embeddings.
- [nomic-embed-text](https://ollama.com/library/nomic-embed-text) – embedding model for Ollama.
- [Chroma + Ollama](https://cookbook.chromadb.dev/integrations/ollama/embeddings) – using Ollama for embeddings in Chroma.
- RAG with Milvus + Ollama, LanceDB + Ollama, and community projects (e.g. ollama-local-rag, OllamaRAG) for full local pipelines.
