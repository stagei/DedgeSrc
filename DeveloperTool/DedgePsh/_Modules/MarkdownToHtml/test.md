# Test Markdown with Mermaid

This is a test markdown file that includes a Mermaid diagram.

## Sample Flowchart

```mermaid
graph TD
    A[Start] --> B{Is it working?}
    B -- Yes --> C[Great!]
    B -- No --> D[Debug]
    D --> B
    C --> E[End]
```

## Sample Sequence Diagram

```mermaid
sequenceDiagram
    participant User
    participant System
    User->>System: Convert Markdown
    System->>System: Process Content
    System->>User: Return HTML
    Note right of System: With Mermaid support!
```

## Regular Markdown

You can also use regular markdown features:

- Bullet points
- **Bold text**
- *Italic text*
- [Links](https://example.com)

### Code Block

```powershell
Get-Process | Where-Object { $_.CPU -gt 10 }
``` 