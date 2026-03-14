# SusuShield — Research Notes

## Self Protocol (ZK Identity)

**What it is:** Self Protocol uses ZK-SNARKs (Groth16) to verify real-world identity attributes (age, nationality, personhood) from government-issued passports via NFC, without revealing raw data. Official Synthesis partner.

**CRITICAL: Self Protocol is Celo-only.** No Base deployment exists as of March 2026. The IdentityVerificationHub V2 is deployed on:
- Celo Mainnet: `0xe57F4773bd9c9d8b6Cd70431117d353298B9f5BF`
- Celo Testnet: `0x16ECBA51e18a4a7e61fdC417f0d47AFEeDfbed74`

**Integration approach (hybrid — off-chain verification + Base contracts):**
1. User scans passport via Self mobile app
2. Self proof verified server-side via `SelfBackendVerifier` (chain-agnostic Node.js)
3. Server issues attestation to Base contract
4. SusuShield.sol checks attestation for `onlyVerified` modifier

**npm packages:**
- `@selfxyz/core` — Backend verifier (`SelfBackendVerifier`)
- `@selfxyz/qrcode` — Frontend QR component (`SelfQRcodeWrapper`, `SelfAppBuilder`)
- `@selfxyz/contracts` — Solidity: `SelfVerificationRoot`, `SelfUtils`

**Frontend config:**
```typescript
const app = new SelfAppBuilder({
  version: 2,
  appName: "SusuShield",
  scope: "susushield",
  endpoint: "https://api.susushield.xyz/verify",
  endpointType: "staging_https", // off-chain for Base
  disclosures: { minimumAge: 18, ofac: true, excludedCountries: ["IRN", "PRK"] }
}).build();
```

**Backend verification:**
```typescript
const verifier = new SelfBackendVerifier("susushield", endpoint, false, AllIds, configStore, "hex");
const result = await verifier.verify(attestationId, proof, publicSignals, userData);
```

**Fallback:** If Self passport scanning is too complex for hackathon demo, use simple address-based identity gate with manual attestation.

**Key URLs:**
- Docs: https://docs.self.xyz
- GitHub: https://github.com/selfxyz/self
- Boilerplate: https://github.com/selfxyz/self-integration-boilerplate

## Locus API (USDC Payments on Base)

**What it is:** "Stripe for AI agents" — managed smart wallets on Base with USDC, policy guardrails, x402 gateway.

**Beta self-registration (agent, no human needed):**
```bash
curl -X POST https://beta-api.paywithlocus.com/api/register \
  -H "Content-Type: application/json" \
  -d '{"name": "SusuShield Agent", "email": "optional@example.com"}'
# Returns: apiKey, ownerPrivateKey, ownerAddress, walletId
# Default: 10 USDC allowance, 5 USDC max per tx
# Rate limit: 5 registrations per IP per hour
```

**Key endpoints:**
| Method | Endpoint | Purpose |
|--------|----------|---------|
| `POST` | `/api/pay/send` | Send USDC to address |
| `GET` | `/api/pay/balance` | Check wallet balance |
| `POST` | `/api/x402/call` | Call any x402-protected API |
| `GET` | `/api/pay/transactions` | Transaction history |

**Send USDC:**
```bash
curl -X POST https://api.paywithlocus.com/api/pay/send \
  -H "Authorization: Bearer YOUR_LOCUS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"to_address": "0xRecipient...", "amount": "5.00", "memo": "Circle payout"}'
```

**Gas is sponsored** (free to sender). Only USDC amount debited.

**npm:** `locus-agent-sdk`

**Fallback:** Direct USDC transfers via contract (already in SusuShield.sol).

## ERC-8004 (Agent Identity) — LIVE ON BASE

**ERC-8004: Trustless Agents** — three onchain registries (Identity, Reputation, Validation) for autonomous AI agents. Launched Jan 29, 2026. ~130K agents across all chains, ~16.5K on Base.

**Base contract addresses:**
| Registry | Address |
|----------|---------|
| Identity Registry | `0x8004A818BFB912233c491871b3d84c89A494BD9e` |
| Reputation Registry | `0x8004B663056A597Dffe9eCcC1965A193B7388713` |

**Registration:**
```solidity
// Call Identity Registry on Base
function register(string agentURI) external returns (uint256 agentId);
// Or with metadata
function register(string agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId);
```

**Agent URI** points to a registration file (IPFS/HTTPS) describing capabilities and endpoints.

**npm packages:**
- `@agentic-trust/8004-sdk` — Core TypeScript SDK
- `@agentic-trust/8004-ext-sdk` — Extended SDK with ENS, multi-chain support

**Reference implementations:**
- https://github.com/erc-8004/erc-8004-contracts (canonical)
- https://github.com/vistara-apps/erc-8004-example (demo)

**Integration for SusuShield:**
1. Register coordinator agent via `register(agentURI)` on Base Identity Registry
2. Get `agentId` (ERC-721 NFT minted to agent wallet)
3. Use `agentId` for onchain reputation tracking
4. Agent wallet handles circle lifecycle operations

## Base Chain Deployment

**Key facts:**
- Gas: ~$0.004 for ETH transfer, ~$0.04 for swap
- USDC: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (**6 decimals, NOT 18**)
- RPC: `https://mainnet.base.org`
- Chain ID: 8453
- Use "onchain" not "on-chain"

**Deployment:**
```bash
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast --verify
```

**TODO (Day 1):**
- [ ] Register Locus beta agent: `POST /api/register`
- [ ] Register ERC-8004 identity on Base
- [ ] Implement SelfBackendVerifier for off-chain identity check
- [ ] Write Deploy.s.sol script
- [ ] Deploy to Base Sepolia first, then mainnet
