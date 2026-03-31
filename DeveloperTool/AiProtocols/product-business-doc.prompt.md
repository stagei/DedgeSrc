# Business Documentation: {{ProductName}}

You are writing a product guide for a non-technical business audience (investors, sales, marketing). The reader has no programming experience.

## Product Context

- **Name:** {{ProductName}}
- **Category:** {{ProductCategory}}
- **Technology Stack:** {{ProductStack}}
- **Description:** {{ProductDescription}}
- **Source folder** (for code inspection): {{CopyToPath}}

If a competitor analysis JSON file was provided as context, use it for the comparison section.

## Document Structure

Write a complete markdown document following this exact section structure:

### 1. Title
`# {{ProductName}} — {catchy tagline summarizing the product}`

### 2. What It Does (The Elevator Pitch)
2-3 paragraphs in plain English. Use an analogy a non-technical person would understand. Explain what the product does and why someone would pay for it.

### 3. The Problem It Solves
Bullet points describing the pain points this product addresses. Use real-world business language, not developer jargon.

### 4. How It Works
Include a **Mermaid flowchart** (`flowchart TD`) showing the high-level data/user flow. Follow with a numbered step-by-step explanation in plain language. Do not use technical terms without explaining them on first use.

### 5. Key Features
Bullet list of the most important capabilities. Each bullet should be understandable without technical background.

### 6. How It Compares to Competitors
A markdown comparison table ({{ProductName}} vs top 3-5 competitors). Include features, pricing, and key differentiators. End with a "Key takeaway" paragraph positioning {{ProductName}} favorably.

### 7. Screenshots
Include this placeholder line:
`![Screenshot](screenshots/{{ProductName}}/main.png)`

### 8. Revenue Potential
- Target market description
- Licensing/pricing model with a tiered pricing table
- Revenue drivers and projections
- Why this product has commercial value

## Writing Rules

- Business English throughout; no code jargon without an inline explanation
- Explain every technical term on first use (e.g., "API — a way for software programs to talk to each other")
- Mermaid diagrams must use valid syntax (no spaces in node IDs, quote labels with special characters)
- Do not wrap the entire response in markdown fences — the response IS the markdown document
- Minimum 800 words, maximum 3000 words
- Do not include any preamble or explanation outside the document itself
