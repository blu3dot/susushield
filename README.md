# SusuShield

> Privacy-preserving savings circles where agents coordinate contributions without revealing who paid how much or when they're getting paid out.

**Synthesis Hackathon 2026** — "Agents that keep secrets" track

## The Problem

ROSCAs (Rotating Savings and Credit Associations) are a $500B+ annual market in the Global South, but existing implementations leak sensitive financial data: who contributed, how much, and when payouts happen. This metadata can be used for discrimination, coercion, or social pressure.

## The Solution

SusuShield brings privacy to savings circles using:

- **Commit-reveal contributions** — Members commit a hash of their contribution amount, then reveal after the deadline. No one sees individual amounts in real-time.
- **ZK identity verification** — Self Protocol proof-of-personhood prevents sybil attacks without revealing personal data.
- **Private reputation** — ZK proofs let members prove "I completed N circles with zero defaults" without revealing which circles.
- **AI agent coordinator** — An ERC-8004 registered agent manages circle lifecycle, contribution reminders, and payout execution via Locus API (USDC on Base).

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Frontend (Next.js)                                      │
│  - Circle creation/joining                               │
│  - Commit/reveal contribution flow                       │
│  - Rotation timeline                                     │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  SusuShield.sol (Base Mainnet)                           │
│  - Commit-reveal contribution scheme                     │
│  - Self Protocol identity gate                           │
│  - Rotation-based payout                                 │
│  - ZK reputation tracking                                │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  Agent Coordinator (ERC-8004)                            │
│  - Circle lifecycle management                           │
│  - Contribution reminders                                │
│  - Payout execution                                      │
│  - Locus API payments (USDC)                             │
└─────────────────────────────────────────────────────────┘
```

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Smart Contracts | Solidity (Foundry) |
| Chain | Base (Ethereum L2) |
| Privacy | Commit-reveal scheme + Self Protocol ZK identity |
| Payments | Locus API (USDC on Base) |
| Agent Identity | ERC-8004 |
| Frontend | Next.js + Tailwind CSS |
| Agent | TypeScript (viem) |

## Quick Start

### Contracts

```bash
cd contracts
forge install
forge build
forge test
```

### Frontend

```bash
npm install
npm run dev
```

## Deployed Contracts

| Contract | Address | Chain |
|----------|---------|-------|
| SusuShield | `TBD` | Base Mainnet |

## How It Works

1. **Create a circle** — Set contribution amount, member count, round duration
2. **Members join** — Self Protocol verifies identity (no personal data shared)
3. **Commit phase** — Members submit hashed contributions (amount hidden)
4. **Reveal phase** — Members reveal amounts, tokens transfer to contract
5. **Payout** — Agent coordinator sends the pot to the round's recipient
6. **Repeat** — Until every member has received their payout

## Human-Agent Collaboration

This project was built through human-agent collaboration. See the `conversationLog/` directory for the full process documentation.

## License

MIT

## Credits

- Built on [nuROSA](https://github.com/blu3dot/nurosa) ROSCA contracts
- Privacy via [Self Protocol](https://self.xyz)
- Payments via [Locus](https://paywithlocus.com)
- Agent identity via ERC-8004
- Ethereum knowledge via [ethskills](https://ethskills.com)
