# SusuShield — Research Notes

## Self Protocol (ZK Identity)

**What it is:** Self Protocol provides ZK identity verification — proof-of-personhood and credential verification without revealing personal data. Official Synthesis hackathon partner for "Agents that keep secrets" track.

**Integration approach for SusuShield:**
- Use Self Protocol for sybil-resistant circle membership
- Members prove they are real humans without revealing identity
- `onlyVerified` modifier on `joinCircle()` and `createCircle()`
- Self Protocol verifier contract validates ZK proofs on-chain

**Fallback:** If Self Protocol SDK is insufficient, use simple Merkle proof identity (whitelist of verified addresses) or commit-reveal based identity attestation.

**Key URLs:**
- https://self.xyz (main site)
- Synthesis partner — listed under "Agents that keep secrets"

**TODO (Day 1):**
- [ ] Find Self Protocol SDK/npm package
- [ ] Review Solidity verifier contract interface
- [ ] Test ZK proof generation flow
- [ ] Check Base chain compatibility

## Locus API (USDC Payments on Base)

**What it is:** Locus provides USDC payment infrastructure on Base — spending controls, pay-per-use APIs, checkout flows. Replaces raw x402 protocol with higher-level abstractions.

**Integration approach for SusuShield:**
- Agent coordinator uses Locus API for contribution reminders with payment links
- Payout execution routes through Locus for Base USDC transfers
- Registration: `POST https://beta-api.paywithlocus.com/api/register`

**Key details:**
- USDC on Base: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`
- Base chain ID: 8453
- RPC: `https://mainnet.base.org`

**Fallback:** Direct USDC transfers via contract (already implemented in SusuShield.sol).

**TODO (Day 1):**
- [ ] Register for Locus API key
- [ ] Test payment flow with small amount
- [ ] Implement Locus checkout for contribution collection

## ERC-8004 (Agent Identity)

**What it is:** Agent identity standard for registering AI agents on-chain. Used at Synthesis for agent registration.

**Integration approach for SusuShield:**
- Register the SusuShield coordinator agent with ERC-8004 on Base
- Agent identity used for `onlyAgent` modifier validation
- Links agent actions to a verifiable on-chain identity

**Synthesis registration:**
- `POST https://synthesis.devfolio.co/register`
- Returns participantId, teamId, apiKey (sk-synth-...)
- On-chain registration transaction

**Fallback:** Simple agent registry contract mapping agent address to metadata.

**TODO (Day 1):**
- [ ] Register with Synthesis platform
- [ ] Get ERC-8004 reference implementation
- [ ] Deploy agent identity on Base

## Base Chain Deployment

**Key facts (from ethskills):**
- Gas costs dramatically reduced in 2026 (~$0.004 for ETH transfer)
- USDC has 6 decimals, NOT 18 (critical for payment math)
- Use "onchain" not "on-chain" (community convention)
- Base RPC: `https://mainnet.base.org`
- USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

**Deployment steps:**
1. Set up `.env` with `PRIVATE_KEY` and `BASE_RPC_URL`
2. `forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast`
3. Verify on Basescan

**TODO (Day 2):**
- [ ] Write Deploy.s.sol script
- [ ] Test on Base Sepolia testnet first
- [ ] Deploy to Base Mainnet
- [ ] Verify contracts on Basescan
