#!/usr/bin/env python3
import sys
sys.path.insert(0, "src/SqlMermaidErdTools/runtimes/win-x64/Lib/site-packages")

from sqlglot import parse, exp

# Test ALTER TABLE parsing
sql = """
ALTER TABLE AdverseEvents
    ADD CONSTRAINT FK_AdverseEvents_Trial
    FOREIGN KEY (TrialID)
    REFERENCES Trials (TrialID)
    ON UPDATE NO ACTION
    ON DELETE NO ACTION;
"""

statements = parse(sql)

print(f"Found {len(statements)} statements")
for i, stmt in enumerate(statements):
    print(f"\n{i}: {type(stmt).__name__}")
    
    if isinstance(stmt, exp.Alter):
        print(f"  Is Alter: YES")
        print(f"  stmt.this: {stmt.this}")
        print(f"  stmt.actions: {stmt.actions if hasattr(stmt, 'actions') else 'NO ACTIONS'}")
        
        if hasattr(stmt, 'actions'):
            for action in stmt.actions:
                print(f"    Action type: {type(action).__name__}")
                print(f"    Action: {action}")
                
                if hasattr(action, 'this'):
                    print(f"      action.this: {action.this}")
                    print(f"      action.this type: {type(action.this).__name__}")

