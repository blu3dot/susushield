# Contributing to SusuShield

## Human-Agent Collaboration

This project is built through human-agent collaboration as part of the Synthesis Hackathon 2026.

### How We Work

1. **Human** sets direction, defines requirements, reviews output
2. **Agent** (Claude Opus 4.6) designs, codes, researches, and documents
3. Every significant session is logged in `conversationLog/`
4. Key decisions are documented in `docs/RESEARCH.md`

### Process

1. Open an issue describing what you want to build
2. Create a branch from `main`
3. Build (human or agent or both)
4. Document the collaboration in `conversationLog/`
5. Open a PR with clear description of changes
6. Get review from at least one human

### Running Locally

```bash
# Contracts
cd contracts && forge build && forge test

# Frontend
npm install && npm run dev
```

### Code Style

- Solidity: Follow OpenZeppelin conventions
- TypeScript: Strict mode, no `any`
- Commit messages: describe the "why", not just the "what"
