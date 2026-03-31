This document provides a comprehensive reference for querying Azure DevOps Boards using WIQL (Work Item Query Language) with the Azure CLI.

## Basic Query Structure

```
az boards query --wiql "SELECT [fields] FROM [table] WHERE [conditions]" --output json
```

## Available Tables

The primary table in Azure DevOps Boards queries is `WorkItems`. This is the main table containing all work item data.

Additional related tables:
- `WorkItemLinks` - Contains relationship data between work items
- `WorkItemRevisions` - Contains historical revisions of work items

## Common System Fields

These fields are available for most work item types:

| Field | Description | Example |
|-------|-------------|---------|
| `System.Id` | Unique identifier for the work item | `SELECT [System.Id] FROM WorkItems` |
| `System.Title` | Title/name of the work item | `WHERE [System.Title] CONTAINS 'migration'` |
| `System.WorkItemType` | Type of work item | `WHERE [System.WorkItemType] = 'Epic'` |
| `System.State` | Current state | `WHERE [System.State] = 'Active'` |
| `System.CreatedBy` | User who created the work item | `WHERE [System.CreatedBy] = 'user@example.com'` |
| `System.CreatedDate` | Creation date | `WHERE [System.CreatedDate] >= '2023-01-01'` |
| `System.ChangedBy` | User who last modified the work item | `WHERE [System.ChangedBy] = 'user@example.com'` |
| `System.ChangedDate` | Last modified date | `WHERE [System.ChangedDate] >= @Today - 7` |
| `System.TeamProject` | Project the work item belongs to | `WHERE [System.TeamProject] = 'MyProject'` |
| `System.AreaPath` | Area path classification | `WHERE [System.AreaPath] UNDER 'MyProject\\Area1'` |
| `System.IterationPath` | Iteration/sprint classification | `WHERE [System.IterationPath] = @CurrentIteration` |
| `System.Tags` | Tags associated with the work item | `WHERE [System.Tags] CONTAINS 'important'` |
| `System.Description` | Detailed description | `WHERE [System.Description] CONTAINS 'keyword'` |
| `System.AssignedTo` | User assigned to the work item | `WHERE [System.AssignedTo] = 'user@example.com'` |
| `System.Reason` | Reason for current state | `WHERE [System.Reason] = 'New'` |

## Process-Specific Fields

### Agile Process Fields

| Field | Description | Example |
|-------|-------------|---------|
| `Microsoft.VSTS.Scheduling.StoryPoints` | Story points estimate | `WHERE [Microsoft.VSTS.Scheduling.StoryPoints] > 5` |
| `Microsoft.VSTS.Common.Priority` | Priority (1-4) | `WHERE [Microsoft.VSTS.Common.Priority] = 1` |
| `Microsoft.VSTS.Common.BusinessValue` | Business value | `WHERE [Microsoft.VSTS.Common.BusinessValue] > 50` |
| `Microsoft.VSTS.Common.ValueArea` | Value area (Business or Architectural) | `WHERE [Microsoft.VSTS.Common.ValueArea] = 'Business'` |

### Scrum Process Fields

| Field | Description | Example |
|-------|-------------|---------|
| `Microsoft.VSTS.Scheduling.Effort` | Effort estimate | `WHERE [Microsoft.VSTS.Scheduling.Effort] > 5` |
| `Microsoft.VSTS.Common.BacklogPriority` | Backlog priority | `WHERE [Microsoft.VSTS.Common.BacklogPriority] < 10` |
| `Microsoft.VSTS.Sprint.TimeCriticality` | Time criticality | `WHERE [Microsoft.VSTS.Sprint.TimeCriticality] > 2` |

### CMMI Process Fields

| Field | Description | Example |
|-------|-------------|---------|
| `Microsoft.VSTS.Scheduling.Size` | Size estimate | `WHERE [Microsoft.VSTS.Scheduling.Size] > 5` |
| `Microsoft.VSTS.CMMI.RequirementType` | Requirement type | `WHERE [Microsoft.VSTS.CMMI.RequirementType] = 'Functional'` |
| `Microsoft.VSTS.Common.Severity` | Severity | `WHERE [Microsoft.VSTS.Common.Severity] = '1 - Critical'` |

## Querying Work Item Links

To query relationships between work items:

```
SELECT [System.Id] FROM WorkItemLinks 
WHERE [Source].[System.Id] = 123 
AND [System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward'
```

Common link types:
- `System.LinkTypes.Hierarchy-Forward` - Parent to child
- `System.LinkTypes.Hierarchy-Reverse` - Child to parent
- `System.LinkTypes.Related` - Related items
- `System.LinkTypes.Dependency-Forward` - Successor
- `System.LinkTypes.Dependency-Reverse` - Predecessor

## Query Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `=` | Equals | `WHERE [System.State] = 'Active'` |
| `<>` | Not equals | `WHERE [System.State] <> 'Closed'` |
| `>`, `>=` | Greater than, Greater than or equal | `WHERE [System.CreatedDate] >= @Today - 30` |
| `<`, `<=` | Less than, Less than or equal | `WHERE [Microsoft.VSTS.Scheduling.StoryPoints] <= 8` |
| `CONTAINS` | Contains substring | `WHERE [System.Title] CONTAINS 'migration'` |
| `NOT CONTAINS` | Does not contain substring | `WHERE [System.Title] NOT CONTAINS 'test'` |
| `IN` | In a list of values | `WHERE [System.State] IN ('Active', 'Resolved')` |
| `NOT IN` | Not in a list of values | `WHERE [System.State] NOT IN ('Closed', 'Removed')` |
| `UNDER` | Under in a hierarchy | `WHERE [System.AreaPath] UNDER 'MyProject\\Area1'` |
| `NOT UNDER` | Not under in a hierarchy | `WHERE [System.AreaPath] NOT UNDER 'MyProject\\Area1'` |
| `EVER` | Ever had a specific value | `WHERE EVER [System.State] = 'Active'` |

## Macros and Variables

| Macro | Description | Example |
|-------|-------------|---------|
| `@Me` | Current user | `WHERE [System.AssignedTo] = @Me` |
| `@Today` | Current date | `WHERE [System.CreatedDate] = @Today` |
| `@Today - n` | n days before today | `WHERE [System.CreatedDate] >= @Today - 7` |
| `@Today + n` | n days after today | `WHERE [System.DueDate] <= @Today + 14` |
| `@CurrentIteration` | Current iteration | `WHERE [System.IterationPath] = @CurrentIteration` |
| `@CurrentIteration +/- n` | Iteration offset | `WHERE [System.IterationPath] = @CurrentIteration + 1` |

## Example Queries

### Find all active user stories assigned to me
```
SELECT [System.Id], [System.Title] FROM WorkItems 
WHERE [System.WorkItemType] = 'User Story' 
AND [System.State] = 'Active' 
AND [System.AssignedTo] = @Me
```

### Find all bugs created in the last 30 days
```
SELECT [System.Id], [System.Title] FROM WorkItems 
WHERE [System.WorkItemType] = 'Bug' 
AND [System.CreatedDate] >= @Today - 30
```

### Find all child work items of a specific epic
```
SELECT [System.Id], [System.Title] FROM WorkItemLinks 
WHERE [Source].[System.Id] = 123 
AND [System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward'
MODE (Recursive)
```

### Find high priority items in the current sprint
```
SELECT [System.Id], [System.Title] FROM WorkItems 
WHERE [System.IterationPath] = @CurrentIteration 
AND [Microsoft.VSTS.Common.Priority] = 1
```
```

I've created a comprehensive reference document for Azure DevOps Boards queries. This document includes:

1. Basic query structure
2. Available tables in Azure DevOps
3. Common system fields with descriptions and examples
4. Process-specific fields for Agile, Scrum, and CMMI processes
5. How to query work item links and relationship types
6. Query operators with examples
7. Macros and variables available in WIQL
8. Example queries for common scenarios

This should help you construct more complex queries using the Azure CLI's `az boards query` command. The document is formatted as a Markdown file that you can reference when building your queries.
