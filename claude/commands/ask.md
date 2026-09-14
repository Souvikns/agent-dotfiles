---
description: Ask a question about the codebase and get a concise, read-only answer
argument-hint: [question]
---

Answer the question below concisely and make no changes.

Delegate to the `ask` subagent: use the Task tool with subagent_type `ask` and
give it the question as the task. Return its answer as-is.

Question: $ARGUMENTS
