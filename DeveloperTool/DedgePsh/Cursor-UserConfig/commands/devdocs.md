**User command (global):** `%USERPROFILE%\.cursor\commands\devdocs.md` — creates generalized technical documentation and publishes to a central docs repository. Works across any workspace; repo-specific paths resolved at runtime.

> **Canonical DevDocs repo:** `C:\opt\src\DevDocs`

---

Create a generalized markdown document on a given theme and publish it to the DevDocs repository.

## Instructions

1. **Determine the topic and subfolder.** Ask the user for the theme if not provided. Map the topic to the correct subfolder in the DevDocs repo:

   | Technology | Folder |
   |---|---|
   | PowerShell | `Powershell/` |
   | Cobol | `Cobol/` |
   | DB2 | `Db2/` |
   | Cursor / LLM / AI | `Cursor and LLM/` |
   | .NET / C# | `.Net/` |
   | CSS / UI | `CSS and UI/` |
   | Windows / VM | `Windows365_Utviklingsmaskiner/` |
   | Other | Create a new folder with title-case naming |

   > **DevDocs path:** `C:\opt\src\DevDocs\<subfolder>\`

2. **Create the markdown file.** Use the naming convention `<Topic Description>.md` (title-case, spaces, hyphens for separators). Include this header:

   ```markdown
   # <Title>

   **Author:** <full name from team config>, www.dEdge.no
   **Created:** <YYYY-MM-DD>
   **Technology:** <technology name>

   ---

   ## Overview

   <Brief description>

   ---
   ```

   Then write comprehensive, well-structured content on the topic. Use headings, code blocks, tables, and diagrams where appropriate. The document should be useful as a standalone reference.

3. **Git commit and push.** Run these commands in the DevDocs repo:

   ```powershell
   cd "<devdocs-repo>"
   git add .
   git commit -m "docs(<folder>): <brief description>"
   git push
   ```

   > **DevDocs repo:** `C:\opt\src\DevDocs`

4. **Deploy to DocView.** If a deploy script exists in the DevDocs repo, run it:

   ```powershell
   pwsh.exe -NoProfile -File "<devdocs-repo>\_deployToDocView.ps1"
   ```

   This copies the DevDocs content to the documentation portal content share and refreshes the cache.

   > **Canonical deploy script:** `C:\opt\src\DevDocs\_deployToDocView.ps1`

5. **Generate portal URL.** After deploy, compute the documentation share UNC path and convert to a clickable URL:

   ```powershell
   Import-Module GlobalFunctions -Force
   $uncPath = "<doc-share-root>\DevDocs\<subfolder>\<filename>.md"
   $docViewUrl = ConvertTo-DocViewUrl $uncPath
   ```

   > **FK DocView share:** `C:\opt\src\DedgeSrc\DedgeSystemTools\Folders\Opt\Webs\DocViewWeb\Content\DevDocs\<subfolder>\<filename>.md`

6. **Confirm** to the user: file path, git push result, deploy result, and the **portal URL as a clickable markdown link**: `[Open in DocView](<url>)`.
