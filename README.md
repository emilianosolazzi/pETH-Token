# pETH — Protocol ETH Reserve Receipt Token

**Network:** Base Mainnet (chain ID 8453)
**Contract:** [`0x017cFe7E298d48A23d521BB409Dbc23D14D2b016`](https://basescan.org/address/0x017cFe7E298d48A23d521BB409Dbc23D14D2b016)
**Protocol UI:** https://peth-eta.vercel.app
**Version:** pETH-IFE-1.3.1

---

## What is pETH?

pETH is a native ETH reserve receipt token. You deposit ETH, you receive pETH 1:1. You burn pETH, you receive ETH back minus a 0.05% redemption fee. Every pETH in circulation is backed by an equal or greater amount of ETH held in the contract.

The backing is not a promise — it is enforced per-transaction by an on-chain invariant:

```
T + F = R       (accounting invariant)
ETH balance ≥ R (physical reserve invariant)
```

- `T` = outstanding pETH supply
- `F` = accumulated protocol fees (not yet swept to treasury)
- `R` = accounted ETH reserve

Any transaction that would violate either condition reverts before completing. You can verify the invariant at any block by calling `checkInvariant()` or reading the boolean `invariant()` on the contract.

---

## Protocol Mechanics

| Action | Function | Fee |
|---|---|---|
| Mint pETH | `mint(address recipient)` payable | 0 bps (free) |
| Burn pETH | `burn(uint256 amount)` | 5 bps (0.05%) |
| Burn to recipient | `burnTo(address recipient, uint256 amount)` | 5 bps (0.05%) |
| Sweep fees to treasury | `sweepFees(uint256 amount)` | treasury only |

Minting is open to any address. Burning is open to any holder. There is no admin mint, no whitelist, no pause, no upgradability.

---

## Contract Properties

| Property | Value |
|---|---|
| Standard | ERC-20 + EIP-2612 permit |
| Decimals | 18 |
| Supply model | Dynamic, fully ETH-backed |
| Hard cap | None (bounded by deposited ETH) |
| Upgradeable | No |
| Pausable | No |
| Admin mint | No |
| Proxy | No |
| Reentrancy guard | Yes |
| Max fee ceiling | 10% (hardcoded) |
| Fee direction | Can only decrease, never increase |

---

## Addresses

| Role | Address |
|---|---|
| Token contract | `0x017cFe7E298d48A23d521BB409Dbc23D14D2b016` |
| Treasury | `0xcF98503836a4DC90fc879CE7F10045B5371571e9` |
| Protocol operator | `0xAa85589DD09C830e8C5196264A1A019Ce26213E7` |

---

## Repository Contents

```
src/
  pETH.sol              — InvariantFirstReserveToken contract (Solidity 0.8.35)
  interface/
    Ipeth.sol           — Full interface with all events and errors
logo/
  pETH-logo.svg         — Full wordmark logo
  pETH-mark.svg         — Icon/mark only
LICENSE                 — MIT
Security.md             — Security properties and vulnerability reporting
BASESCAN_TOKEN_SUBMISSION.md  — Detailed Basescan token submission document
```

---

## Security

See [Security.md](Security.md) for invariant properties, reentrancy protection, fee bounds, and vulnerability reporting instructions.

To report a security vulnerability: **coma.retained@gmail.com** with subject `[pETH SECURITY]`.

---

## License

MIT — see [LICENSE](LICENSE).
