// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title InvariantFirstReserveToken
/// @notice ERC20-compatible, EIP-2612 permit-enabled, native-ETH reserve receipt token.
/// @dev Native ETH collateral reference implementation.
///      State tuple:
///        R = accounted reserve held by this contract
///        T = outstanding redeemable token supply
///        F = protocol fee slice inside reserve
///
///      Core invariant:
///        T + F == R
///
///      Physical reserve invariant:
///        address(this).balance >= R
///
///      Valid economic transitions:
///        mint(x):   (R, T, F) -> (R + x,       T + (x - f), F + f)
///        burn(x):   (R, T, F) -> (R - (x - f), T - x,       F + f)
///        sweep(y):  (R, T, F) -> (R - y,       T,           F - y), y <= F
///        transfer:  no change to (R, T, F)
///
///      Novelty:
///        This treats solvency as a transaction-validity condition, not as an external proof-of-reserves report.
contract InvariantFirstReserveToken {
    // =============================================================
    //                           ERRORS
    // =============================================================

    error ZeroAmount();
    error ZeroAddress();
    error EmptyMetadata();
    error InvalidReceiver(address receiver);
    error FeeTooHigh(uint256 feeBps, uint256 maxFeeBps);
    error FeeAmountTooLarge(uint256 amount, uint256 feeBps);
    error NotTreasury(address caller, address treasury);
    error NotPendingTreasury(address caller);
    error NoPendingTreasuryTransfer();
    error InsufficientBalance(address account, uint256 requested, uint256 available);
    error InsufficientAllowance(address owner, address spender, uint256 requested, uint256 available);
    error InvariantViolation(uint256 T, uint256 F, uint256 R);
    error InvariantOverflow(uint256 T, uint256 F);
    error ReserveShortfall(uint256 actualBalance, uint256 accountedReserve);
    error SweepExceedsFees(uint256 requested, uint256 accumulatedFees);
    error SurplusTooSmall(uint256 requested, uint256 available);
    error ETHTransferFailed(address to, uint256 amount);
    error Reentrancy();
    error DirectETHNotAccepted();
    error CannotIncreaseFee(uint256 current, uint256 requested);
    error PermitExpired(uint256 deadline);
    error InvalidPermitSignature();

    // =============================================================
    //                         ERC20 METADATA
    // =============================================================

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    // =============================================================
    //                          STATE TUPLE
    // =============================================================

    /// @notice Accounted reserve backing this system, denominated in wei.
    // slither-disable-next-line naming-convention
    uint256 public R;

    /// @notice Outstanding token supply, denominated in token units.
    // slither-disable-next-line naming-convention
    uint256 public T;

    /// @notice Fee slice retained inside reserve, denominated in wei.
    // slither-disable-next-line naming-convention
    uint256 public F;

    // =============================================================
    //                         ERC20 STORAGE
    // =============================================================

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // =============================================================
    //                          EIP-2612
    // =============================================================

    mapping(address => uint256) public nonces;

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes32 private constant _EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _VERSION_HASH = keccak256("1");
    uint256 private constant _SECP256K1_HALF_ORDER =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    bytes32 private immutable _hashedName;
    uint256 private immutable _initialChainId;
    bytes32 private immutable _initialDomainSeparator;

    // =============================================================
    //                         CONFIGURATION
    // =============================================================

    address public treasury;
    address public pendingTreasury;
    /// @notice Mint fee in basis points; 1 = 0.01%, 100 = 1.00%.
    uint256 public mintFeeBps;
    /// @notice Burn fee in basis points; 1 = 0.01%, 100 = 1.00%.
    uint256 public burnFeeBps;

    uint256 public constant BPS_DENOMINATOR = 100_00; // 100.00%
    uint256 public constant MAX_FEE_BPS = 10_00; // 10.00%

    // =============================================================
    //                       REENTRANCY GUARD
    // =============================================================

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    // =============================================================
    //                            EVENTS
    // =============================================================

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event Mint(
        address indexed caller,
        address indexed to,
        uint256 grossDeposit,
        uint256 fee,
        uint256 minted,
        uint256 RNew,
        uint256 TNew,
        uint256 FNew
    );

    event Burn(
        address indexed caller,
        address indexed receiver,
        uint256 burned,
        uint256 fee,
        uint256 released,
        uint256 RNew,
        uint256 TNew,
        uint256 FNew
    );

    event Sweep(
        address indexed treasury,
        uint256 amount,
        uint256 RNew,
        uint256 FNew
    );

    event SurplusAbsorbedAsFees(
        uint256 amount,
        uint256 RNew,
        uint256 FNew
    );

    event TreasuryTransferInitiated(address indexed currentTreasury, address indexed pendingTreasury_);
    event TreasuryTransferCompleted(address indexed oldTreasury, address indexed newTreasury);
    event TreasuryTransferCancelled(address indexed cancelledPending);

    event MintFeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event BurnFeeBpsUpdated(uint256 oldBps, uint256 newBps);

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    modifier nonReentrant() {
        if (_status == _ENTERED) revert Reentrancy();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    modifier onlyTreasury() {
        if (msg.sender != treasury) revert NotTreasury(msg.sender, treasury);
        _;
    }

    /// @notice Enforces the accounting and physical reserve invariants after function execution.
    modifier invariantGuard() {
        _;
        _assertInvariant();
    }

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(
        string memory name_,
        string memory symbol_,
        address treasury_,
        uint256 mintFeeBps_,
        uint256 burnFeeBps_
    ) {
        if (bytes(name_).length == 0) revert EmptyMetadata();
        if (bytes(symbol_).length == 0) revert EmptyMetadata();
        if (treasury_ == address(0)) revert ZeroAddress();
        if (mintFeeBps_ > MAX_FEE_BPS) revert FeeTooHigh(mintFeeBps_, MAX_FEE_BPS);
        if (burnFeeBps_ > MAX_FEE_BPS) revert FeeTooHigh(burnFeeBps_, MAX_FEE_BPS);

        name = name_;
        symbol = symbol_;
        treasury = treasury_;
        mintFeeBps = mintFeeBps_;
        burnFeeBps = burnFeeBps_;
        _status = _NOT_ENTERED;
        _hashedName = keccak256(bytes(name_));
        _initialChainId = block.chainid;
        _initialDomainSeparator = _buildDomainSeparator();
    }

    // =============================================================
    //                         ERC20 VIEWS
    // =============================================================

    function totalSupply() external view returns (uint256) {
        return T;
    }

    // =============================================================
    //                        MINT / WRAP
    // =============================================================

    /// @notice Deposits ETH and mints redeemable receipt tokens.
    /// @param to Recipient of minted tokens.
    /// @return minted Amount of tokens minted.
    ///
    /// @dev Fee-from-backing transition:
    ///      (R, T, F) -> (R + x, T + (x - f), F + f)
    ///
    ///      Strict mode:
    ///      Set mintFeeBps = 0.
    function mint(address to)
        external
        payable
        nonReentrant
        invariantGuard
        returns (uint256 minted)
    {
        minted = _depositETH(to, msg.value);
    }

    // =============================================================
    //                        BURN / UNWRAP
    // =============================================================

    /// @notice Burns caller tokens and releases ETH back to caller.
    /// @param amount Amount of tokens to burn.
    /// @return released Amount of ETH released.
    function burn(uint256 amount)
        external
        nonReentrant
        invariantGuard
        returns (uint256 released)
    {
        released = _burnTo(msg.sender, payable(msg.sender), amount);
    }

    /// @notice Burns caller tokens and releases ETH to a chosen receiver.
    /// @param receiver ETH receiver.
    /// @param amount Amount of tokens to burn.
    /// @return released Amount of ETH released.
    function burnTo(address payable receiver, uint256 amount)
        external
        nonReentrant
        invariantGuard
        returns (uint256 released)
    {
        if (receiver == address(0)) revert ZeroAddress();
        if (receiver == address(this)) revert InvalidReceiver(receiver);
        released = _burnTo(msg.sender, receiver, amount);
    }

    /// @dev Fee-from-backing burn transition:
    ///      (R, T, F) -> (R - (x - f), T - x, F + f)
    ///
    ///      Critical correction:
    ///      R decreases by the released amount, not the gross burned amount.
    function _burnTo(address owner, address payable receiver, uint256 amount)
        internal
        returns (uint256 released)
    {
        if (amount == 0) revert ZeroAmount();

        uint256 ownerBalance = balanceOf[owner];
        if (ownerBalance < amount) {
            revert InsufficientBalance(owner, amount, ownerBalance);
        }

        uint256 f = _burnFee(amount);
        released = amount - f;
        if (released == 0) revert ZeroAmount();

        balanceOf[owner] = ownerBalance - amount;

        T -= amount;
        F += f;
        R -= released;

        emit Transfer(owner, address(0), amount);
        emit Burn(owner, receiver, amount, f, released, R, T, F);

        _sendETH(receiver, released);
    }

    // =============================================================
    //                         FEE SWEEP
    // =============================================================

    /// @notice Sweeps accumulated protocol fees to treasury.
    /// @param amount Amount of fee reserve to sweep.
    ///
    /// @dev Sweep transition:
    ///      (R, T, F) -> (R - y, T, F - y), where y <= F.
    ///
    ///      This cannot touch user backing because y is bounded by F.
    function sweepFees(uint256 amount)
        external
        onlyTreasury
        nonReentrant
        invariantGuard
    {
        if (amount == 0) revert ZeroAmount();
        if (amount > F) revert SweepExceedsFees(amount, F);

        F -= amount;
        R -= amount;

        emit Sweep(treasury, amount, R, F);

        _sendETH(payable(treasury), amount);
    }

    // =============================================================
    //                 FORCED-ETH / SURPLUS HANDLING
    // =============================================================

    /// @notice Returns ETH held above accounted reserve R.
    /// @dev ETH can be force-sent via selfdestruct-like mechanisms.
    ///      Surplus is not user backing unless explicitly absorbed.
    function surplus() public view returns (uint256) {
        uint256 bal = address(this).balance;
        if (bal <= R) return 0;
        return bal - R;
    }

    /// @notice Converts forced or accidental ETH surplus into fee-attributed reserve.
    /// @param amount Amount of surplus to absorb as protocol fees.
    ///
    /// @dev Transition:
    ///      (R, T, F) -> (R + y, T, F + y)
    ///
    ///      This preserves T + F == R and makes surplus sweepable as fees.
    function absorbSurplusAsFees(uint256 amount)
        external
        onlyTreasury
        nonReentrant
        invariantGuard
    {
        if (amount == 0) revert ZeroAmount();

        uint256 available = surplus();
        if (amount > available) revert SurplusTooSmall(amount, available);

        R += amount;
        F += amount;

        emit SurplusAbsorbedAsFees(amount, R, F);
    }

    // =============================================================
    //                     TREASURY ROTATION
    // =============================================================

    /// @notice Step 1: current treasury nominates a new treasury address.
    /// @dev The new treasury must call acceptTreasuryTransfer() to take effect.
    function initiateTreasuryTransfer(address newTreasury) external onlyTreasury {
        if (newTreasury == address(0)) revert ZeroAddress();
        if (newTreasury == address(this)) revert InvalidReceiver(newTreasury);
        if (pendingTreasury != address(0)) emit TreasuryTransferCancelled(pendingTreasury);
        pendingTreasury = newTreasury;
        emit TreasuryTransferInitiated(treasury, newTreasury);
    }

    /// @notice Step 2: the nominated address accepts and becomes the new treasury.
    function acceptTreasuryTransfer() external {
        if (msg.sender != pendingTreasury) revert NotPendingTreasury(msg.sender);
        address old = treasury;
        treasury = pendingTreasury;
        pendingTreasury = address(0);
        emit TreasuryTransferCompleted(old, treasury);
    }

    /// @notice Current treasury cancels a pending transfer before it is accepted.
    function cancelTreasuryTransfer() external onlyTreasury {
        if (pendingTreasury == address(0)) revert NoPendingTreasuryTransfer();
        address cancelled = pendingTreasury;
        pendingTreasury = address(0);
        emit TreasuryTransferCancelled(cancelled);
    }

    // =============================================================
    //                       FEE MANAGEMENT
    // =============================================================

    /// @notice Lowers the mint fee. Fees may only decrease — never increase.
    function setMintFeeBps(uint256 newFeeBps) external onlyTreasury {
        if (newFeeBps >= mintFeeBps) revert CannotIncreaseFee(mintFeeBps, newFeeBps);
        emit MintFeeBpsUpdated(mintFeeBps, newFeeBps);
        mintFeeBps = newFeeBps;
    }

    /// @notice Lowers the burn fee. Fees may only decrease — never increase.
    function setBurnFeeBps(uint256 newFeeBps) external onlyTreasury {
        if (newFeeBps >= burnFeeBps) revert CannotIncreaseFee(burnFeeBps, newFeeBps);
        emit BurnFeeBpsUpdated(burnFeeBps, newFeeBps);
        burnFeeBps = newFeeBps;
    }

    // =============================================================
    //                       ERC20 TRANSFERS
    // =============================================================

    /// @notice Transfers tokens without changing global reserve state.
    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Approves spender.
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfers tokens using allowance without changing global reserve state.
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (from == address(0)) revert ZeroAddress();
        _spendAllowanceIfNeeded(from, msg.sender, amount);

        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();

        uint256 newAllowance = allowance[msg.sender][spender] + addedValue;
        _approve(msg.sender, spender, newAllowance);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();

        uint256 currentAllowance = allowance[msg.sender][spender];
        if (currentAllowance < subtractedValue) {
            revert InsufficientAllowance(msg.sender, spender, subtractedValue, currentAllowance);
        }

        uint256 newAllowance = currentAllowance - subtractedValue;
        _approve(msg.sender, spender, newAllowance);
        return true;
    }

    // =============================================================
    //                           PERMIT
    // =============================================================

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        if (block.chainid == _initialChainId) return _initialDomainSeparator;
        return _buildDomainSeparator();
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (owner == address(0)) revert ZeroAddress();
        if (spender == address(0)) revert ZeroAddress();
        if (block.timestamp > deadline) revert PermitExpired(deadline);
        if (v != 27 && v != 28) revert InvalidPermitSignature();
        if (uint256(s) > _SECP256K1_HALF_ORDER) revert InvalidPermitSignature();

        uint256 nonce = nonces[owner];
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        address recovered = ecrecover(digest, v, r, s);
        if (recovered != owner) revert InvalidPermitSignature();

        nonces[owner] = nonce + 1;
        _approve(owner, spender, value);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        if (to == address(this)) revert InvalidReceiver(to);

        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) {
            revert InsufficientBalance(from, amount, fromBalance);
        }

        balanceOf[from] = fromBalance - amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }

    // =============================================================
    //                         VIEW HELPERS
    // =============================================================

    /// @notice Returns the full invariant state tuple.
    function stateTuple()
        external
        view
        returns (
            uint256 accountedReserve,
            uint256 outstandingSupply,
            uint256 accumulatedFees,
            uint256 actualETHBalance
        )
    {
        return (R, T, F, address(this).balance);
    }

    /// @notice Returns whether both accounting and physical reserve invariants hold.
    function invariant() external view returns (bool) {
        if (T > type(uint256).max - F) {
            return false;
        }

        return T + F == R && address(this).balance >= R;
    }

    /// @notice Returns whether both accounting and physical reserve invariants hold.
    function checkInvariant()
        external
        view
        returns (
            bool holds,
            uint256 accountingDiff,
            uint256 reserveShortfallAmount,
            uint256 surplusAmount
        )
    {
        uint256 lhs;

        if (T > type(uint256).max - F) {
            return (false, type(uint256).max, 0, surplus());
        }

        lhs = T + F;

        if (lhs >= R) {
            accountingDiff = lhs - R;
        } else {
            accountingDiff = R - lhs;
        }

        uint256 bal = address(this).balance;

        if (bal < R) {
            reserveShortfallAmount = R - bal;
            surplusAmount = 0;
        } else {
            reserveShortfallAmount = 0;
            surplusAmount = bal - R;
        }

        // slither-disable-start incorrect-equality
        holds = accountingDiff == 0 && reserveShortfallAmount == 0;
        // slither-disable-end incorrect-equality
    }

    /// @notice Fee for a gross mint deposit.
    function calculateMintFee(uint256 amount) external view returns (uint256) {
        return _mintFee(amount);
    }

    /// @notice Fee for a burn amount.
    function calculateBurnFee(uint256 amount) external view returns (uint256) {
        return _burnFee(amount);
    }

    /// @notice Preview deposit result including the configured mint fee.
    function previewDepositWithFee(uint256 grossDeposit)
        external
        view
        returns (uint256 fee, uint256 minted)
    {
        fee = _mintFee(grossDeposit);
        minted = grossDeposit - fee;
    }

    /// @notice Preview burn result.
    function previewBurn(uint256 burnAmount)
        external
        view
        returns (uint256 fee, uint256 released)
    {
        fee = _burnFee(burnAmount);
        released = burnAmount - fee;
    }

    /// @notice Reserve-to-supply ratio in basis points.
    /// @dev R / T includes fee-attributed reserve F.
    ///      If T == 0, system has no outstanding user claims.
    function reserveToSupplyRatioBps() public view returns (uint256) {
        if (T == 0) return type(uint256).max;

        // slither-disable-start divide-before-multiply
        // forge-lint: disable-next-line(divide-before-multiply)
        return ((R / T) * BPS_DENOMINATOR) + (((R % T) * BPS_DENOMINATOR) / T);
        // slither-disable-end divide-before-multiply
    }

    /// @notice Backward-compatible alias for reserveToSupplyRatioBps().
    function collateralizationRatioBps() external view returns (uint256) {
        return reserveToSupplyRatioBps();
    }

    /// @notice Max redeem preview for a specific user at current state.
    function maxRedeemable(address user)
        external
        view
        returns (uint256 burnAmount, uint256 fee, uint256 released)
    {
        burnAmount = balanceOf[user];
        fee = _burnFee(burnAmount);
        released = burnAmount - fee;
    }

    /// @notice Preview cumulative fee drag over N complete mint→burn roundtrips.
    /// @param amount  Starting ETH (gross deposit each cycle).
    /// @param periods Number of roundtrip cycles; capped at 1000.
    /// @return totalFeeDrag Total ETH consumed by fees across all periods.
    /// @return finalAmount  Remaining ETH after all periods complete.
    function previewCumulativeFeeDrag(uint256 amount, uint256 periods)
        external
        view
        returns (uint256 totalFeeDrag, uint256 finalAmount)
    {
        if (periods > 1000) periods = 1000;
        uint256 current = amount;
        for (uint256 i = 0; i < periods; ) {
            uint256 mf = _mintFee(current);
            uint256 tokens = current - mf;
            if (tokens == 0) break;
            uint256 bf = _burnFee(tokens);
            uint256 received = tokens - bf;
            totalFeeDrag += mf + bf;
            current = received;
            unchecked { ++i; }
        }
        finalAmount = current;
    }

    /// @notice Semantic version for telemetry and integrations.
    function version() external pure returns (string memory) {
        return "pETH-IFE-1.3.1";
    }

    /// @notice User-redeemable backing equals outstanding supply T under this model.
    function userRedeemableBacking() external view returns (uint256) {
        return T;
    }

    /// @notice Protocol-owned fee backing equals F.
    function protocolFeeBacking() external view returns (uint256) {
        return F;
    }

    // =============================================================
    //                         INTERNALS
    // =============================================================

    function _depositETH(address to, uint256 assets)
        internal
        returns (uint256 minted)
    {
        if (assets == 0) revert ZeroAmount();
        if (to == address(0)) revert ZeroAddress();
        if (to == address(this)) revert InvalidReceiver(to);

        uint256 f = _mintFee(assets);

        minted = assets - f;
        if (minted == 0) revert ZeroAmount();

        R += assets;
        T += minted;
        F += f;

        balanceOf[to] += minted;

        emit Transfer(address(0), to, minted);
        emit Mint(msg.sender, to, assets, f, minted, R, T, F);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) revert ZeroAddress();
        if (spender == address(0)) revert ZeroAddress();

        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowanceIfNeeded(address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) revert ZeroAddress();
        if (spender == owner) return;

        uint256 currentAllowance = allowance[owner][spender];

        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) {
                revert InsufficientAllowance(owner, spender, amount, currentAllowance);
            }

            _approve(owner, spender, currentAllowance - amount);
        }
    }

    function _buildDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                _EIP712_DOMAIN_TYPEHASH,
                _hashedName,
                _VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    function _assertInvariant() internal view {
        if (T > type(uint256).max - F) {
            revert InvariantOverflow(T, F);
        }

        uint256 lhs = T + F;

        if (lhs != R) {
            revert InvariantViolation(T, F, R);
        }

        uint256 actual = address(this).balance;

        if (actual < R) {
            revert ReserveShortfall(actual, R);
        }
    }

    /// @dev Mint fee. Returns 0 immediately when mintFeeBps == 0.
    function _mintFee(uint256 amount) internal view returns (uint256) {
        if (mintFeeBps == 0) return 0;
        return _fee(amount, mintFeeBps);
    }

    /// @dev Burn fee. Returns 0 immediately when burnFeeBps == 0.
    function _burnFee(uint256 amount) internal view returns (uint256) {
        if (burnFeeBps == 0) return 0;
        return _fee(amount, burnFeeBps);
    }

    function _fee(uint256 amount, uint256 feeBps) internal pure returns (uint256) {
        return ((amount / BPS_DENOMINATOR) * feeBps)
            + (((amount % BPS_DENOMINATOR) * feeBps) / BPS_DENOMINATOR);
    }

    function _sendETH(address payable to, uint256 amount) internal {
        // slither-disable-next-line low-level-calls
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert ETHTransferFailed(to, amount);
    }

    // =============================================================
    //                    DIRECT ETH TRANSFERS BLOCKED
    // =============================================================

    receive() external payable {
        revert DirectETHNotAccepted();
    }

    fallback() external payable {
        revert DirectETHNotAccepted();
    }
}
