# Security

## Reporting a Vulnerability

To report a security vulnerability in the pETH contract, contact the project operator directly:

- **Email:** coma.retained@gmail.com
- **Subject:** `[pETH SECURITY] <brief description>`

Please do not open a public GitHub issue for security vulnerabilities.

## Security Properties

The `InvariantFirstReserveToken` contract enforces the following invariants on every state-changing call:

### Accounting Invariant (T + F = R)

- `T` (outstanding supply) + `F` (accumulated fees) must equal `R` (accounted reserve) at the end of every transaction.
- Any transition that would violate this constraint causes the transaction to revert via `InvariantViolation`.

### Physical Reserve Invariant (ETH balance ≥ R)

- The contract's native ETH balance must be greater than or equal to `R` at all times.
- Any transition that would leave the physical reserve short reverts via `ReserveShortfall`.

### No Admin Mint

- There is no privileged mint function. The only way to create pETH is to send ETH via `mint(address)`.
- pETH is minted 1:1 against deposited ETH (minus any mint fee, currently 0 bps).

### No Proxy, No Upgrade

- The contract is non-proxy and non-upgradeable. The source code deployed at the contract address is the entire protocol.

### Reentrancy Protection

- All state-changing functions (`mint`, `burn`, `burnTo`, `sweepFees`, `absorbSurplusAsFees`) are guarded by a mutex-based reentrancy lock.
- The invariant guard is applied after every state-modifying call to confirm the invariant holds before the call completes.

### Fee Bounds

- Mint and burn fees are bounded at a maximum of 10% (`MAX_FEE_BPS = 1000`).
- Fees can only be **decreased** after deployment, never increased (`CannotIncreaseFee`).

### EIP-2612 Permit Anti-Malleability

- Permit signatures enforce `s <= SECP256K1_HALF_ORDER` and `v ∈ {27, 28}`.
- The domain separator is chain-fork-aware and re-computed after chain ID changes.

## Audit Status

The pETH contract has not undergone a third-party security audit as of the initial Base deployment. The source code is fully verified on Basescan. The invariant is enforced per transaction and is validated by 188 Foundry tests including fuzz tests at 5,000,000 calls per invariant property.

## Known Limitations

- Treasury address is a single EOA on the current deployment. A multi-sig upgrade path exists via `initiateTreasuryTransfer` / `acceptTreasuryTransfer`.
- Small amounts (below the fee threshold) may result in zero fee collection due to integer truncation — this is documented and does not affect the invariant.
