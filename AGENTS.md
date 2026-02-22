# Project: ray-agents

## Multi-Agent System

This project is managed by two AI agents coordinated through GitHub issues:
- **Manager Agent**: Creates and manages issues based on the project goal. Never writes code.
- **SWE Agent**: Picks up issues and implements them. Never manages issues beyond commenting.

## GitHub Issue Protocol

### Labels
| Label | Meaning |
|-------|---------|
| `ready` | Issue is available for the SWE agent to pick up |
| `in-progress` | SWE agent is actively working on this issue |
| `blocked` | SWE agent could not complete; needs manager attention |
| `completed` | Work is finished; issue will be closed |

### Issue Body Format
Every issue must contain:
1. **Objective**: What needs to be done and why
2. **Acceptance Criteria**: Checkboxes defining "done"
3. **Context**: Relevant file paths, related issues, technical details
4. **Dependencies**: Other issues that must be completed first, or "None"

### Comment Conventions
- SWE starting work: "Claimed. Starting implementation."
- SWE blocked: "BLOCKED: <reason>"
- SWE done: "Implementation complete. ... Closing."
- Manager unblocking: "Unblocked: <explanation>"

## Code Conventions
- Commit messages reference issue numbers: "Implement #42: Add user auth"
- No force pushes
- No direct pushes from agents (human reviews and pushes)
- Follow existing code style in the repository
- Do not introduce new dependencies without explicit issue approval

## File Ownership
| File | Owner | Other Agents |
|------|-------|--------------|
| `goal.md` | Human | Read-only |
| `memory.md` | Manager | Do not touch |
| `run.sh` | Human | Do not touch |
| `opencode.json` | Human | Do not touch |
| `AGENTS.md` | Human | Do not touch |
| Source code | SWE | Manager reads only |
