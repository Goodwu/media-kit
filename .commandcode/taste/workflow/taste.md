# Workflow

- Wants conclusions and review results written into markdown files in the repo, not only summarized in chat. Confidence: 0.85
- When asking for a plan, expects it to be actionable and grounded: concrete design plus step-by-step verification/validation steps, and the related requirement doc updated as part of the work. Confidence: 0.85
- Orchestrates work by handing tasks to other agents; asks for the exact entry point / starting file so the agent can begin without re-discovery. Confidence: 0.8
- Reviews already-made commits against the project's original framework/architecture and asks whether the scheme is reasonable and improvable — wants consistency with existing design checked explicitly. Confidence: 0.8
- Prefers doing requirement and architecture review before implementation starts. Confidence: 0.7
- Keeps requirement docs in `docs/requirements/` as the source of truth and expects them kept in sync with the implementation. Confidence: 0.7
