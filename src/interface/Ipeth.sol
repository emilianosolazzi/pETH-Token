// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @title IPETH
/// @notice Interface for pETH: an invariant-first ERC20 receipt token with EIP-2612 permit.
interface IPETH {
    // =============================================================
    //                           EVENTS
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

    event Sweep(address indexed treasury, uint256 amount, uint256 RNew, uint256 FNew);
    event SurplusAbsorbedAsFees(uint256 amount, uint256 RNew, uint256 FNew);
    event TreasuryTransferInitiated(address indexed currentTreasury, address indexed pendingTreasury_);
    event TreasuryTransferCompleted(address indexed oldTreasury, address indexed newTreasury);
    event TreasuryTransferCancelled(address indexed cancelledPending);
    event MintFeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event BurnFeeBpsUpdated(uint256 oldBps, uint256 newBps);

    // =============================================================
    //                         ERC20 / PERMIT
    // =============================================================

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    // =============================================================
    //                         PETH CORE API
    // =============================================================

    function mint(address to) external payable returns (uint256 minted);
    function burn(uint256 amount) external returns (uint256 released);
    function burnTo(address payable receiver, uint256 amount) external returns (uint256 released);

    function R() external view returns (uint256);
    function T() external view returns (uint256);
    function F() external view returns (uint256);

    function treasury() external view returns (address);
    function pendingTreasury() external view returns (address);
    function mintFeeBps() external view returns (uint256);
    function burnFeeBps() external view returns (uint256);
    function BPS_DENOMINATOR() external view returns (uint256);
    function MAX_FEE_BPS() external view returns (uint256);

    function sweepFees(uint256 amount) external;
    function surplus() external view returns (uint256);
    function absorbSurplusAsFees(uint256 amount) external;
    function initiateTreasuryTransfer(address newTreasury) external;
    function acceptTreasuryTransfer() external;
    function cancelTreasuryTransfer() external;
    function setMintFeeBps(uint256 newFeeBps) external;
    function setBurnFeeBps(uint256 newFeeBps) external;

    function stateTuple()
        external
        view
        returns (
            uint256 accountedReserve,
            uint256 outstandingSupply,
            uint256 accumulatedFees,
            uint256 actualETHBalance
        );

    function invariant() external view returns (bool);
    function checkInvariant()
        external
        view
        returns (
            bool holds,
            uint256 accountingDiff,
            uint256 reserveShortfallAmount,
            uint256 surplusAmount
        );

    function calculateMintFee(uint256 amount) external view returns (uint256);
    function calculateBurnFee(uint256 amount) external view returns (uint256);
    function previewDepositWithFee(uint256 grossDeposit)
        external
        view
        returns (uint256 fee, uint256 minted);
    function previewBurn(uint256 burnAmount) external view returns (uint256 fee, uint256 released);
    function reserveToSupplyRatioBps() external view returns (uint256);
    function collateralizationRatioBps() external view returns (uint256);
    function maxRedeemable(address user)
        external
        view
        returns (uint256 burnAmount, uint256 fee, uint256 released);
    function previewCumulativeFeeDrag(uint256 amount, uint256 periods)
        external
        view
        returns (uint256 totalFeeDrag, uint256 finalAmount);
    function version() external pure returns (string memory);
    function userRedeemableBacking() external view returns (uint256);
    function protocolFeeBacking() external view returns (uint256);
}
