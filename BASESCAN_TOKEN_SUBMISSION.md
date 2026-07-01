# Basescan Token Information Submission — pETH

**Submission date:** 2026-07-01
**Submitted by:** Emiliano Solazzi, project founder and protocol operator
**Sender email:** coma.retained@gmail.com
**Project website:** https://peth-eta.vercel.app
**Code repository:** https://github.com/emilianosolazzi/pETH-Token
**Scope:** Token identity, project facts, governance disclosure, anti-misrepresentation, and non-infringement for pETH on Base Mainnet.

This document is the single source of truth for Basescan's review. Every claim is verifiable on-chain against the contract listed below.

---

## 1. Token Summary

| Field | Value |
|---|---|
| **Token name** | pETH |
| **Symbol** | pETH |
| **Standard** | ERC-20 (immutable, non-upgradeable, non-pausable) + EIP-2612 permit |
| **Decimals** | 18 |
| **Supply model** | Dynamic — fully collateralized by native ETH held in reserve |
| **Hard cap** | None — supply is bounded by total ETH deposited |
| **Network** | Base Mainnet (chain ID 8453) |
| **Token contract** | `0x017cFe7E298d48A23d521BB409Dbc23D14D2b016` (verified on Basescan) |
| **Mint mechanism** | Public — any address may call `mint(address)` with ETH attached; minted 1:1 against ETH deposited |
| **Burn mechanism** | Public — any holder may call `burn(uint256)` to redeem ETH at a 0.05% redemption fee |
| **Admin mint** | None. No privileged mint function exists. |
| **Upgrade / proxy** | None. Non-proxy, non-upgradeable. |
| **Mint fee** | 0 bps (free entry) |
| **Burn fee** | 5 bps (0.05% redemption fee, capped at 10% by contract) |
| **Protocol version** | pETH-IFE-1.3.1 (`InvariantFirstReserveToken`) |

The pETH contract enforces a two-part solvency condition on every state-changing call:

- **Accounting invariant:** `T + F == R`
  - `T` = outstanding pETH supply, `F` = accumulated protocol fees, `R` = accounted ETH reserve
- **Physical reserve invariant:** `ETH balance ≥ R`

Any transaction that would violate either condition reverts before completing. Solvency is a per-transaction validity condition, not a periodic external attestation.

---

## 2. Project Summary (plain, factual, non-promotional)

pETH is a native ETH reserve receipt token deployed on Base. Every deposited ETH is held in the contract's reserve and accounted for in the state tuple `(R, T, F)`. Every outstanding pETH represents a redeemable claim on ETH held by the protocol, with accounting enforced by the invariant `T + F = R` and physical backing enforced by `ETH balance ≥ R`.

The protocol's role is narrow:

1. **Wrap ETH → pETH:** Send ETH via `mint(address)`. Receive pETH 1:1 (no mint fee). ETH is deposited into reserve (`R += ETH_in`, `T += ETH_in`).
2. **Unwrap pETH → ETH:** Burn pETH via `burn(uint256)`. Receive ETH minus 0.05% redemption fee. The fee accrues to `F`, not to `R`, maintaining the invariant.
3. **Fee sweep:** The treasury calls `sweepFees(amount)` to collect accumulated `F` denominated in ETH. This reduces `R` and `F` symmetrically, maintaining the invariant.

There is **no token sale, no airdrop, no presale, and no public ICO.** Every pETH in existence was minted by a user depositing ETH directly into the contract. The protocol does not hold funds beyond what users deposited.

---

## 3. Current On-Chain State (verifiable)

As of submission date (2026-07-01):

| Metric | Function | Value |
|---|---|---|
| `totalSupply()` | ERC-20 standard | ~0.00115 ETH equivalent |
| `R()` | Accounted reserve | ≥ T + F (invariant verified) |
| `T()` | Outstanding supply | equals `totalSupply()` |
| `F()` | Accumulated fees | small (few burns completed) |
| `invariant()` | On-chain check | returns `true` every block |
| Mint fee | `mintFeeBps()` | 0 bps |
| Burn fee | `burnFeeBps()` | 5 bps |

All values readable directly from the verified contract on Basescan without any off-chain intermediary.

---

## 4. Governance and Control Disclosure

- **Protocol operator:** `0xAa85589DD09C830e8C5196264A1A019Ce26213E7` — the wallet that deployed the contract and executed the first mint. No privileged on-contract mint capability beyond what any user has.
- **Treasury (fee recipient):** `0xcF98503836a4DC90fc879CE7F10045B5371571e9` — receives swept fees via `sweepFees()`. May be rotated via a two-step `initiateTreasuryTransfer` / `acceptTreasuryTransfer` process; rotation requires the pending treasury to actively accept.
- **Fee governance:** Burn fee is immutable-upward — it can be decreased from 5 bps but never increased beyond 5 bps (`CannotIncreaseFee` error). Max fee is hardcoded at 10% and unreachable from the current 5 bps without lowering first.
- **Upgradability:** None. No proxy, no implementation slot, no `delegatecall`. The deployed bytecode is the complete protocol.
- **Pause mechanism:** None. There is no pause function, no emergency stop, and no circuit breaker in the contract.

---

## 5. Name and Symbol Non-Infringement Statement

To the knowledge of the project operator, **"pETH" as used in this context does not infringe any existing trademark or registered mark** of a third party operating under the same ticker on Base Mainnet.

The name "pETH" is a direct descriptor: **p** for "protocol" or "proof-of-reserve", **ETH** for the underlying native asset. It describes what the token is — an ETH receipt token with on-chain reserve accounting — rather than referencing any third-party brand.

The project acknowledges that several ETH-derivative tokens exist across different chains (e.g. liquid staking derivatives). pETH is not associated with, and does not imply endorsement by, any such project, exchange, foundation, or financial institution. pETH is not a liquid staking token, does not accrue yield, and does not represent staked ETH. It is a plain reserve receipt: deposit ETH, receive pETH, redeem pETH for ETH.

If Basescan identifies a name / symbol conflict, the project is available to provide clarifying disclosures or to accommodate Basescan's resolution guidance.

---

## 6. Sender Authority

The submission is sent from `coma.retained@gmail.com`. The protocol operator wallet is `0xAa85589DD09C830e8C5196264A1A019Ce26213E7`.

To demonstrate that this submission is authorized by the actual contract operator, the following verification paths are available on request:

1. **On-chain signed message** — the operator wallet signs a challenge phrase provided by Basescan, posted to a public transaction or IPFS.
2. **Transaction-based proof** — a zero-value Base transaction from the operator wallet carrying a Basescan-provided calldata memo.
3. **Verified-contract authorship** — the source code of `InvariantFirstReserveToken` at `0x017cFe7E298d48A23d521BB409Dbc23D14D2b016` is verified on Basescan against the deployer address. The GitHub repository at `https://github.com/emilianosolazzi/pETH-Token` is published under the same GitHub account as the Arbiscan-approved TGBT project (`https://github.com/emilianosolazzi/TGBT_Token`), establishing continuity of identity.

The project will provide whichever verification path Basescan prefers.

---

## 7. Founder / Team Transparency

- **Founder and protocol operator:** Emiliano Solazzi
- **LinkedIn:** https://www.linkedin.com/in/emiliano-germ%C3%A1n-solazzi-griminger-936717210/
- **Code repository:** https://github.com/emilianosolazzi/pETH-Token
- **Protocol UI:** https://peth-eta.vercel.app
- **Prior approved submission:** TGBT token on Arbitrum One — approved by Arbiscan (same operator, same GitHub account, same identity verification chain)
- **Role:** sole maintainer of this repository, deployer of the Base contract, and the party responsible for this submission.
- **Jurisdiction statement:** pETH is a developer-led open-source protocol. It is not a registered investment product, is not marketed as one, and makes no forward-looking financial promises in any of its materials.

---

## 8. Anti-Misrepresentation Declarations

1. **No false claims of partnership.** pETH is not endorsed by, affiliated with, or partnered with the Base network, Coinbase, the Ethereum Foundation, or any exchange or financial institution. The protocol runs on Base as an independent deployment with no relationship to Base's infrastructure team beyond using the public network.
2. **No false claims of security or audit.** pETH has not undergone a third-party security audit. Source code is public and verified on Basescan. The project does not use the word "audited" anywhere in its user-facing materials.
3. **No investment solicitation.** pETH is described exclusively as a reserve receipt token — a technical primitive for on-chain ETH accounting. No marketing copy describes it as an investment product, a yield vehicle, or a store of value.
4. **No misrepresentation of technology.** All claims in the UI and documentation correspond to behaviour implemented in the verified on-chain contract. The invariant `T + F = R` is enforced per-transaction and verifiable at any block via `checkInvariant()` or `invariant()`.
5. **No misrepresentation of supply or backing.** pETH totalSupply always equals the ETH deposited minus redemptions, minus fees swept. The physical ETH balance of the contract always meets or exceeds `R`. No pETH can be minted without an equal ETH deposit.

---

## 9. Contract and Transaction Appendix

**Deployment on Base Mainnet (chain ID 8453):**

| Item | Value |
|---|---|
| Token contract | `0x017cFe7E298d48A23d521BB409Dbc23D14D2b016` |
| Basescan | https://basescan.org/address/0x017cFe7E298d48A23d521BB409Dbc23D14D2b016 |
| Contract name | `InvariantFirstReserveToken` |
| Protocol version | `pETH-IFE-1.3.1` |
| Solidity version | `0.8.35` |
| License | MIT |
| Treasury | `0xcF98503836a4DC90fc879CE7F10045B5371571e9` |
| Operator wallet | `0xAa85589DD09C830e8C5196264A1A019Ce26213E7` |

**First protocol transactions (operator wallet):**

| Action | Transaction |
|---|---|
| First mint (0.00098 ETH) | `0x0429b307d2f31ad446fbf5f15de15647bb340653dfce24094823272aa4c21b34` |
| First burn | `0x37a7b0dbb580d465877222d47616afa620ee3e5e3585a3ad6697c9947fd2f082` |

---

## 10. What We Are Asking Basescan To Do

1. Approve token information for pETH at `0x017cFe7E298d48A23d521BB409Dbc23D14D2b016` using the facts in §1–§4 of this document.
2. Display the token name as **pETH**, symbol **pETH**, decimals **18**, and link to the project website `https://peth-eta.vercel.app`.
3. Accept the authority verification described in §6, or advise which alternative verification path is preferred.
4. Note the prior Arbiscan-approved submission (TGBT / `https://arbiscan.io/token/0x31228eE520e895DA19f728DE5459b1b317d9b8D8`) as an established identity reference for the same operator.

The project is available to respond promptly to any reviewer question through the same submission channel.

— end of document —
