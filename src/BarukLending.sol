// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./BarukYieldFarm.sol";
import "./interfaces/ISeiOracle.sol";

contract BarukLending {
    address public governance;
    mapping(address => mapping(address => uint256)) public deposits; // user => asset => amount
    mapping(address => mapping(address => uint256)) public borrows;  // user => asset => amount

    event Deposited(address indexed user, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount, address collateral);
    event Repaid(address indexed user, address indexed asset, uint256 amount);
    event Liquidated(address indexed user, address indexed collateral, uint256 amount);
    event ProtocolFeeSet(uint256 newFeeBps, address newTreasury);
    event ProtocolFeeAccrued(address indexed treasury, uint256 amount);
    event ProtocolFeeClaimed(address indexed treasury, uint256 amount);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);

    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    // Integration: YieldFarm reserve and AMM price oracle
    BarukYieldFarm public yieldFarm;
    // Assume a price oracle interface (to be implemented)
    // function getPrice(address token) external view returns (uint256 priceInUSD);

    // Collateralization ratios (e.g., 150% required)
    uint256 public constant COLLATERAL_FACTOR = 150; // 150%

    ISeiOracle constant ORACLE = ISeiOracle(0x0000000000000000000000000000000000001008);
    uint64 public constant PRICE_LOOKBACK_SECONDS = 60;
    uint64 public constant PRICE_STALENESS_THRESHOLD = 60;

    // Dynamic mapping from token address to denom string
    mapping(address => string) public tokenDenoms;
    event TokenDenomSet(address indexed token, string denom);

    // Protocol fee and treasury
    uint256 public protocolFeeBps = 5; // 0.05% default
    address public protocolTreasury;
    uint256 public protocolFeesAccrued;

    bool public paused;

    constructor(address _yieldFarm) {
        governance = msg.sender;
        yieldFarm = BarukYieldFarm(_yieldFarm);
    }

    // Check available liquidity in the farm for a token
    function availableLiquidity(address token) public view returns (uint256) {
        return yieldFarm.availableReserve(token);
    }

    function deposit(address asset, uint256 amount) external whenNotPaused {
        require(amount > 0, "Zero amount");
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        deposits[msg.sender][asset] += amount;
        emit Deposited(msg.sender, asset, amount);
    }

    function borrow(address asset, uint256 amount, address collateral) external whenNotPaused {
        // Collateral and risk checks
        uint256 collateralValue = getCollateralValue(msg.sender, collateral);
        uint256 borrowValue = getBorrowValue(asset, amount);
        require(collateralValue >= borrowValue * COLLATERAL_FACTOR / 100, "Insufficient collateral");
        // Use farm's reserve
        require(yieldFarm.availableReserve(asset) >= amount, "Insufficient liquidity in farm");
        uint256 protocolFee = (amount * protocolFeeBps) / 10000;
        protocolFeesAccrued += protocolFee;
        emit ProtocolFeeAccrued(protocolTreasury, protocolFee);
        uint256 amountAfterFee = amount - protocolFee;
        yieldFarm.lendOut(asset, msg.sender, amountAfterFee);
        borrows[msg.sender][asset] += amountAfterFee;
        emit Borrowed(msg.sender, asset, amountAfterFee, collateral);
    }

    function repay(address asset, uint256 amount) external whenNotPaused {
        require(amount > 0, "Zero amount");
        uint256 protocolFee = (amount * protocolFeeBps) / 10000;
        protocolFeesAccrued += protocolFee;
        emit ProtocolFeeAccrued(protocolTreasury, protocolFee);
        uint256 amountAfterFee = amount - protocolFee;
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        borrows[msg.sender][asset] -= amountAfterFee;
        emit Repaid(msg.sender, asset, amountAfterFee);
    }

    function liquidate(address user, address collateral) external onlyGovernance whenNotPaused {
        // If user's health factor < 1, liquidate
        require(healthFactor(user, collateral) < 1e18, "Healthy position");
        // Liquidation logic to be implemented (e.g., transfer collateral to protocol)
        emit Liquidated(user, collateral, 0);
    }

    // Dynamic TWAP fetcher using mapping
    function getTokenTwap(address token) public view returns (uint256 price, int64 oracleLastUpdate) {
        string memory denom = tokenDenoms[token];
        require(bytes(denom).length > 0, "No denom set");
        (price, oracleLastUpdate) = getTwap(denom);
        require(price > 0, "No price");
        require(block.timestamp - uint64(oracleLastUpdate) <= PRICE_STALENESS_THRESHOLD, "Stale price");
    }

    // Update getCollateralValue and getBorrowValue to use dynamic token
    function getCollateralValue(address user, address collateral) public view returns (uint256) {
        (uint256 price, ) = getTokenTwap(collateral);
        return deposits[user][collateral] * price / 1e18;
    }
    function getBorrowValue(address asset, uint256 amount) public view returns (uint256) {
        (uint256 price, ) = getTokenTwap(asset);
        return amount * price / 1e18;
    }

    function healthFactor(address user, address collateral) public view returns (uint256) {
        uint256 collateralValue = getCollateralValue(user, collateral);
        uint256 totalBorrowed;
        // Sum all borrows (in this example, just one asset)
        // In a real system, sum across all borrowed assets
        totalBorrowed = borrows[user][collateral];
        if (totalBorrowed == 0) return type(uint256).max;
        return (collateralValue * 1e18) / (totalBorrowed * COLLATERAL_FACTOR / 100);
    }

    // Helper to parse string to uint256 (simple version, for demo)
    function parseStringToUint(string memory s) internal pure returns (uint256 result) {
        bytes memory b = bytes(s);
        for (uint i = 0; i < b.length; i++) {
            if (b[i] >= 0x30 && b[i] <= 0x39) {
                result = result * 10 + (uint8(b[i]) - 48);
            }
        }
    }

    // Governance function to set token-denom mapping
    function setTokenDenom(address token, string calldata denom) external onlyGovernance {
        tokenDenoms[token] = denom;
        emit TokenDenomSet(token, denom);
    }

    function getTwap(string memory denom) public view returns (uint256 price, int64 oracleLastUpdate) {
        ISeiOracle.OracleTwap[] memory twaps = ORACLE.getOracleTwaps(PRICE_LOOKBACK_SECONDS);
        for (uint i = 0; i < twaps.length; i++) {
            if (keccak256(abi.encodePacked(twaps[i].denom)) == keccak256(abi.encodePacked(denom))) {
                price = parseStringToUint(twaps[i].twap);
                oracleLastUpdate = twaps[i].lookbackSeconds;
                return (price, oracleLastUpdate);
            }
        }
        return (0, 0);
    }

    // Governance function to set protocol fee and treasury
    function setProtocolFee(uint256 newFeeBps, address newTreasury) external onlyGovernance {
        require(newFeeBps <= 100, "Fee too high");
        protocolFeeBps = newFeeBps;
        protocolTreasury = newTreasury;
        emit ProtocolFeeSet(newFeeBps, newTreasury);
    }

    // Protocol can claim accrued fees
    function claimProtocolFees() external {
        require(msg.sender == protocolTreasury, "Not treasury");
        uint256 amount = protocolFeesAccrued;
        require(amount > 0, "No fees");
        protocolFeesAccrued = 0;
        // Assume protocol fees are in the asset with the most accrued (for demo, use ETH or a default asset)
        payable(protocolTreasury).transfer(amount);
        emit ProtocolFeeClaimed(protocolTreasury, amount);
    }

    function setGovernance(address newGovernance) external onlyGovernance {
        require(newGovernance != address(0), "Zero address");
        emit GovernanceTransferred(governance, newGovernance);
        governance = newGovernance;
    }
    function pause() external onlyGovernance {
        require(!paused, "Already paused");
        paused = true;
        emit Paused(msg.sender);
    }
    function unpause() external onlyGovernance {
        require(paused, "Not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }

    function depositAndBorrow(
        address collateral,
        uint256 depositAmount,
        address asset,
        uint256 borrowAmount
    ) external whenNotPaused {
        require(depositAmount > 0, "Zero deposit");
        require(borrowAmount > 0, "Zero borrow");

        // Transfer collateral from user
        IERC20(collateral).transferFrom(msg.sender, address(this), depositAmount);
        deposits[msg.sender][collateral] += depositAmount;
        emit Deposited(msg.sender, collateral, depositAmount);

        // Now perform the borrow logic
        uint256 collateralValue = getCollateralValue(msg.sender, collateral);
        uint256 borrowValue = getBorrowValue(asset, borrowAmount);
        require(collateralValue >= borrowValue * COLLATERAL_FACTOR / 100, "Insufficient collateral");
        require(yieldFarm.availableReserve(asset) >= borrowAmount, "Insufficient liquidity in farm");
        uint256 protocolFee = (borrowAmount * protocolFeeBps) / 10000;
        protocolFeesAccrued += protocolFee;
        emit ProtocolFeeAccrued(protocolTreasury, protocolFee);
        uint256 amountAfterFee = borrowAmount - protocolFee;
        yieldFarm.lendOut(asset, msg.sender, amountAfterFee);
        borrows[msg.sender][asset] += amountAfterFee;
        emit Borrowed(msg.sender, asset, amountAfterFee, collateral);
    }
} 