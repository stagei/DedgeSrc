# Check Existing Rules Before Starting Work

Before making any changes or starting a new task, search `.cursor/rules/` for rules that may apply to the current work.

## Required Steps

1. **Read the task** — understand what technology, framework, or pattern is involved
2. **List rules** — scan `.cursor/rules/*.mdc` filenames for relevant keywords
3. **Read matching rules** — open and follow any rule whose description or filename relates to the task
4. **Apply the rules** — follow captured learnings, patterns, and checklists from matched rules

## When to Search

- Starting a new project or feature
- Working with a technology you have rules for (WordPress, PowerShell, HTML, APIs, etc.)
- Encountering an error — check if a rule already documents the fix
- Before deployment — check for deployment checklists or gotchas
- Converting between formats or platforms — check for conversion guides

## How to Match

Match rules by **filename keywords**, **description**, and **globs**:

- Task involves WordPress? Check rules with `wp-`, `wordpress`, `theme` in the name
- Task involves PowerShell? Check rules with `ps-`, `powershell`, `deploy` in the name
- Task involves HTML/CSS/JS? Check rules with `html`, `static`, `frontend` in the name
- Task involves a conversion? Check rules with `to-wordpress`, `to-html`, `convert`, `migrate`
- Hit an error? Search rule descriptions for the error type or technology

## Do Not Skip This

Even if you think you know how to do something, an existing rule may contain a project-specific gotcha, a hosting quirk, or a user preference that overrides the default approach. Checking takes seconds and prevents repeating past mistakes.

