# PowerShell Core Unapproved Verbs and Function Naming Restrictions

## Unapproved Verbs in PowerShell Core

PowerShell has a set of approved verbs that should be used when naming cmdlets and functions. Using unapproved verbs will generate warnings when you create modules or run certain commands.

Here's a list of common unapproved verbs that people sometimes try to use:

- Activate
- Browse
- Calculate
- Check
- Configure
- Create
- Delete
- Download
- End
- Execute
- Find
- Flush
- Initialize
- Interact
- Launch
- List
- Load
- Make
- Navigate
- Notify
- Parse
- Ping
- Print
- Process
- Query
- Run
- Save
- Search
- Setup
- Start
- Terminate
- Uninstall
- Upload
- Validate
- Verify
- Wait

Instead, you should use the approved verbs that can be listed with:

```powershell
Get-Verb
```

## Unapproved Letters for Function Names

In PowerShell, function names should follow the `Verb-Noun` format. The first character of a function name should be a letter (A-Z, a-z).

Characters that are not allowed as the first character of a function name:

- Numbers (0-9)
- Special characters (!, @, #, $, %, ^, &, *, etc.)
- Spaces
- Underscores (_)
- Hyphens (-)

Additionally, PowerShell function names are not case-sensitive, so `Get-Process` and `get-process` are treated as the same function.

To check if a verb is approved, you can use:

```powershell
Get-Verb | Where-Object { $_.Verb -eq "YourVerb" }
```

If this returns no results, the verb is not approved.
