# Portfolio Update: Dedge Business Portfolio

You are updating the master business portfolio document for Dedge, a software company with {{TotalProducts}} products.

## Task

Regenerate the complete `Dedge-Business-Portfolio.md` document. The _BusinessDocs folder is provided as context — it contains per-product markdown files and competitor analyses. The existing portfolio is attached as a context file.

## Product Catalog (from all-projects.json)

{{ProductListJson}}

## Document Structure

The portfolio must follow this structure:

### Front Matter
- Title: `# Dedge Product Portfolio — Complete Business Guide`
- Confidentiality notice and last-updated date (use today's date)
- "About This Document" section explaining audience and reading instructions

### Quick Reference Card
A wide markdown table with columns: #, Product Name, Category, One-Line Pitch, Revenue Potential, Top Competitor. One row per product, numbered sequentially.

### How to Read This Guide
Numbered list of the document's major parts.

### Part 1: The Big Picture
- 30-second elevator pitch for Dedge as a company
- Product categories overview with a Mermaid flowchart showing all categories and product counts

### Parts 2-8: Product Categories
Group products by category. For each product include:
- What it does (2-3 sentences, plain English)
- Key features (bullets)
- Competitor positioning (brief)
- Revenue potential (brief)

Use the per-product .md files from _BusinessDocs as source material. Summarize — do not copy entire files.

### Part 9: Business Strategy
- Revenue models (SaaS, licensing, consulting)
- Go-to-market strategy
- Market opportunities
- Pricing philosophy

### Part 10: How to Demo Each Product
Brief demo script / talking points per product.

### Part 11: Screenshot Gallery
Reference screenshot paths for products that have them.

### Glossary
Define every technical term used in the document.

## Writing Rules

- Business English for a non-technical audience (investors, sales, marketing)
- Explain every technical term on first use
- Include Mermaid diagrams where they aid understanding (category overview, architecture, data flows)
- Mermaid syntax: no spaces in node IDs, quote labels with special characters, no style/classDef
- Do not wrap the response in markdown fences — the response IS the document
- The document should be comprehensive (2000-3000 lines) but not repetitive
- Do not include any preamble or meta-commentary outside the document
