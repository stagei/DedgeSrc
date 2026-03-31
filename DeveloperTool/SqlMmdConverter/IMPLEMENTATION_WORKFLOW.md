# Implementation Workflow - Automated Agent-Driven Development

## Overview

SqlMmdConverter follows an automated, agent-driven development workflow where the Cursor agent autonomously implements the entire solution based on specifications, with minimal human intervention.

## Automated Code Review Process

Before marking any task as **completed**, the agent must verify:

### 1. Specification Compliance
- ✅ All functionality described in the related specification document is implemented
- ✅ All requirements from the spec are addressed
- ✅ No specified features are missing or partially implemented

### 2. Code Quality Standards
- ✅ Follows C# 13 / .NET 10 conventions
- ✅ Uses nullable reference types where appropriate
- ✅ Follows Microsoft naming conventions
- ✅ One class per file, namespace matches folder structure
- ✅ XML documentation comments on all public APIs
- ✅ Proper error handling with custom exceptions

### 3. Testing Requirements
- ✅ Unit tests written for all new functionality
- ✅ Integration tests for end-to-end scenarios
- ✅ All tests passing
- ✅ Test coverage meets minimum threshold (>80%)
- ✅ Reference data tests working (SQL→MMD and MMD→SQL)

### 4. Documentation
- ✅ XML comments on public APIs
- ✅ README updated if needed
- ✅ Sample code updated if needed
- ✅ Specification documents current

### 5. Build Quality
- ✅ No build errors
- ✅ No build warnings
- ✅ No new linter errors introduced
- ✅ Code analyzer rules passing

### 6. File Verification
- ✅ All required files created
- ✅ Proper file structure maintained
- ✅ No temporary files left behind

## Task Completion Checklist

For each task, the agent will:

```
1. READ specification document linked to task
2. IMPLEMENT functionality according to spec
3. WRITE unit tests for implementation
4. WRITE integration tests if applicable
5. RUN tests to verify they pass
6. CHECK for linter errors
7. VERIFY against specification (automated review)
8. UPDATE documentation if needed
9. MARK task as completed ONLY if all checks pass
10. MOVE to next task
```

## Exception Handling

The agent will pause and request user input only when:

- ❌ Specification is ambiguous or contradictory
- ❌ External dependency cannot be downloaded/accessed
- ❌ Platform-specific issue that cannot be resolved
- ❌ Unresolvable build or runtime error
- ❌ Test failures that cannot be diagnosed automatically

Otherwise, the agent continues autonomously.

## Task Dependencies

Tasks are organized with explicit dependencies:

- **Sequential Tasks**: Must complete in order (e.g., models before parsers)
- **Parallel Tasks**: Can be done in any order (e.g., different test suites)
- **Blocking Tasks**: Must complete before dependent tasks can start

## Progress Tracking

The agent maintains:

- ✅ **Todo List**: All tasks with current status
- ✅ **Specification Links**: Each task links to relevant spec document
- ✅ **Completion Criteria**: Clear definition of "done" for each task
- ✅ **Automated Validation**: Verification checklist for each task

## Continuous Integration

As tasks complete, the agent ensures:

1. **Incremental Builds**: Project builds successfully after each task
2. **Test Suite Growth**: Tests accumulate and all pass
3. **Documentation Current**: Docs stay synchronized with code
4. **No Regression**: Previous functionality remains working

## Task Granularity

Tasks are sized to be:

- **Specific**: Clear, well-defined scope
- **Testable**: Can be verified objectively
- **Atomic**: Complete unit of work
- **Documented**: Links to specification
- **Reviewable**: Can be validated against criteria

## Specification Documents

Each task references one or more of:

- `.cursorrules` - Core project rules and conventions
- `BACKEND_COMPONENTS.md` - External tool integration
- `BUNDLING_STRATEGY.md` - Runtime bundling approach
- `TESTING_STRATEGY.md` - Test infrastructure and approach
- `IMPLEMENTATION_WORKFLOW.md` - This document

## Workflow Example

```
Task: "Create TableDefinition model class"
├─ Spec: .cursorrules (Models section)
├─ Implementation:
│  ├─ Create src/SqlMmdConverter/Models/TableDefinition.cs
│  ├─ Add properties per spec
│  ├─ Add XML documentation
│  ├─ Add validation logic
├─ Testing:
│  ├─ Create TableDefinitionTests.cs
│  ├─ Test validation rules
│  ├─ Test serialization
├─ Verification:
│  ├─ Check: All properties from spec present?
│  ├─ Check: XML comments on public members?
│  ├─ Check: Tests written and passing?
│  ├─ Check: No linter errors?
│  ├─ Check: Follows naming conventions?
├─ Result: ✅ All checks passed
└─ Status: COMPLETED
```

## Quality Gates

No task is marked complete unless:

1. **Code compiles** without errors or warnings
2. **Tests pass** (all new and existing)
3. **Spec requirements met** (100% of specified functionality)
4. **Documentation complete** (XML comments, README updates)
5. **No regressions** (previous tests still pass)
6. **Linter clean** (no new linter errors)

## Autonomous Decision Making

The agent is empowered to:

- ✅ Choose implementation details not specified in docs
- ✅ Refactor code for clarity and maintainability
- ✅ Add helper methods/classes as needed
- ✅ Improve error messages and logging
- ✅ Optimize code structure
- ✅ Add defensive checks and validation
- ❌ Change public APIs without spec update
- ❌ Skip tests or documentation
- ❌ Ignore specification requirements
- ❌ Leave tasks partially complete

## Success Criteria

The project is complete when:

1. ✅ All tasks marked as completed
2. ✅ All specifications fully implemented
3. ✅ All tests passing (>80% coverage)
4. ✅ NuGet package builds successfully
5. ✅ Sample applications run correctly
6. ✅ Documentation complete and accurate
7. ✅ No build warnings or linter errors
8. ✅ Round-trip tests pass (SQL↔MMD↔SQL)

## Reporting

The agent provides status updates showing:

- Current task being worked on
- Progress percentage
- Recent completions
- Next task to be started
- Any blockers encountered

