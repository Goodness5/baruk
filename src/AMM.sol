// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IAmm.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/ISeiOracle.sol";

contract BarukAMM is IBarukAMM, ReentrancyGuard, ERC20 {
    address public token0;
    address public token1;
    bool public initialized;
    address public factory;
    address public governance;
    uint256 private _reserve0;
    uint256 private _reserve1;
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidityBalance;
    uint256 private constant MINIMUM_LIQUIDITY = 10**3;
    bool public paused;
    uint256 private _price0CumulativeLast;
    uint256 private _price1CumulativeLast;
    uint32 private _lastUpdateTimestamp;
    // Events for analytics/yield/limit order hooks
    event Swap(address indexed user, uint256 amountIn, uint256 amountOut, address tokenIn, address tokenOut);
    // Dynamic mapping from token address to denom string
    mapping(address => string) public tokenDenoms;
    event TokenDenomSet(address indexed token, string denom);
    // Flash loan logic
    uint256 public flashLoanFeeBps = 8; // 0.08% fee
    event FlashLoan(address indexed borrower, address indexed token, uint256 amount, uint256 fee);
    // Incentives for liquidity providers
    uint256 public lpFeeBps = 25; // 0.25% of each swap goes to LPs
    mapping(address => uint256) public lpRewards;
    event LPRewardAccrued(address indexed provider, uint256 amount);
    event LPRewardClaimed(address indexed provider, uint256 amount);
    event AnalyticsAddLiquidity(address indexed user, uint256 amount0, uint256 amount1, uint256 liquidity, uint256 blockNumber);
    event AnalyticsRemoveLiquidity(address indexed user, uint256 amount0, uint256 amount1, uint256 liquidity, uint256 blockNumber);
    // Protocol fee and treasury
    uint256 public protocolFeeBps = 5; // 0.05% default
    address public protocolTreasury;
    event ProtocolFeeSet(uint256 newFeeBps, address newTreasury);
    event ProtocolFeeAccrued(address indexed treasury, uint256 amount);
    event ProtocolFeeClaimed(address indexed treasury, uint256 amount);
    uint256 public protocolFeesAccrued;
    // Batch operations
    event BatchSwap(address indexed user, uint256 count);
    event BatchAddLiquidity(address indexed user, uint256 count);
    event BatchRemoveLiquidity(address indexed user, uint256 count);

    // Custom errors
    error ArithmeticOverflow(string operation);
    error DivisionByZero();
    error InvalidToken();
    error InsufficientLiquidity();
    error TransferFailed();
    error SlippageTooHigh();
    error ContractPaused();
    error NotGovernance();

    ISeiOracle constant ORACLE = ISeiOracle(0x0000000000000000000000000000000000001008);
    uint64 public constant PRICE_LOOKBACK_SECONDS = 60;
    uint64 public constant PRICE_STALENESS_THRESHOLD = 60;

    constructor() ERC20("Baruk AMM LP", "BRK-LP") {}

    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }

    modifier whenNotPaused() {
        require(paused == false, "Pool paused");
        _;
        
    }

    function initialize(address _token0, address _token1) external {
        require(!initialized, "Already initialized");
        token0 = _token0;
        token1 = _token1;
        initialized = true;
    }

    function updatePriceOracle() internal {
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - _lastUpdateTimestamp;
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            _price0CumulativeLast += (_reserve1 / _reserve0) * timeElapsed;
            _price1CumulativeLast += (_reserve0 / _reserve1) * timeElapsed;
            _lastUpdateTimestamp = blockTimestamp;
        }
    }

    function pause() external override onlyGovernance {
        paused = true;
        emit Paused();
    }

    function unpause() external override onlyGovernance {
        paused = false;
        emit Unpaused();
    }

    // --- Interface Getters ---

    function price0CumulativeLast() external view override returns (uint256) {
        return _price0CumulativeLast;
    }
    function price1CumulativeLast() external view override returns (uint256) {
        return _price1CumulativeLast;
    }
    function lastUpdateTimestamp() external view override returns (uint32) {
        return _lastUpdateTimestamp;
    }
    function getReserves() external view override returns (uint256 reserve0, uint256 reserve1) {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }

    function addLiquidity(
        uint256 amount0,
        uint256 amount1,
        address to
    ) public override nonReentrant whenNotPaused returns (uint256 liquidity) {
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidity();
        uint256 reserve0 = _reserve0;
        uint256 reserve1 = _reserve1;
        if (reserve0 == 0 && reserve1 == 0) {
            liquidity = sqrt(amount0 * amount1);
            if (liquidity <= MINIMUM_LIQUIDITY) revert ArithmeticOverflow("Initial liquidity too low");
            liquidity -= MINIMUM_LIQUIDITY;
        } else {
            uint256 amount1Optimal = (amount0 * reserve1) / reserve0;
            if (amount1 < amount1Optimal) revert InsufficientLiquidity();
            liquidity = (amount0 * totalLiquidity) / reserve0;
        }
        if (!IERC20(token0).transferFrom(msg.sender, address(this), amount0)) revert TransferFailed();
        if (!IERC20(token1).transferFrom(msg.sender, address(this), amount1)) revert TransferFailed();
        if (_reserve0 + amount0 < _reserve0) revert ArithmeticOverflow("reserve0 addition");
        if (_reserve1 + amount1 < _reserve1) revert ArithmeticOverflow("reserve1 addition");
        if (totalLiquidity + liquidity < totalLiquidity) revert ArithmeticOverflow("totalLiquidity addition");
        _reserve0 += amount0;
        _reserve1 += amount1;
        totalLiquidity += liquidity;
        _mint(to, liquidity);
        liquidityBalance[to] += liquidity;
        updatePriceOracle();
        emit LiquidityAdded(to, amount0, amount1, liquidity, _reserve0, _reserve1);
        emit AnalyticsAddLiquidity(to, amount0, amount1, liquidity, block.number);
    }

    function removeLiquidity(
        uint256 liquidity
    ) public override nonReentrant whenNotPaused returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0 || liquidityBalance[msg.sender] < liquidity) revert InsufficientLiquidity();
        amount0 = (liquidity * _reserve0) / totalLiquidity;
        amount1 = (liquidity * _reserve1) / totalLiquidity;
        if (liquidityBalance[msg.sender] < liquidity) revert ArithmeticOverflow("liquidityBalance subtraction");
        if (totalLiquidity < liquidity) revert ArithmeticOverflow("totalLiquidity subtraction");
        if (_reserve0 < amount0) revert ArithmeticOverflow("reserve0 subtraction");
        if (_reserve1 < amount1) revert ArithmeticOverflow("reserve1 subtraction");
        liquidityBalance[msg.sender] -= liquidity;
        totalLiquidity -= liquidity;
        _reserve0 -= amount0;
        _reserve1 -= amount1;
        _burn(msg.sender, liquidity); // Burn ERC20 liquidity tokens
        if (!IERC20(token0).transfer(msg.sender, amount0)) revert TransferFailed();
        if (!IERC20(token1).transfer(msg.sender, amount1)) revert TransferFailed();
        updatePriceOracle();
        emit LiquidityRemoved(msg.sender, amount0, amount1, liquidity, _reserve0, _reserve1);
        emit AnalyticsRemoveLiquidity(msg.sender, amount0, amount1, liquidity, block.number);
    }

    // Place helper functions before their first usage
    function _handleFeesAndReturnNetIn(uint256 amountInActual, address user) internal returns (uint256) {
        uint256 protocolFee = (amountInActual * protocolFeeBps) / 10000;
        uint256 lpFee = (amountInActual * lpFeeBps) / 10000;
        protocolFeesAccrued += protocolFee;
        lpRewards[user] += lpFee;
        emit ProtocolFeeAccrued(protocolTreasury, protocolFee);
        emit LPRewardAccrued(user, lpFee);
        return amountInActual - protocolFee - lpFee;
    }
    function _doTransferOut(IERC20 token, address to, uint256 amount) internal {
        require(token.transfer(to, amount), "Transfer failed");
    }
    function _emitSwap(address user, uint256 amountInActual, uint256 amountOut, address tokenIn, address tokenOut) internal {
        emit Swap(user, amountInActual, amountOut, tokenIn, tokenOut);
    }

    function _swap(
        uint256 amountIn,
        address tokenIn,
        uint256 minAmountOut,
        address recipient
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientLiquidity();
        if (tokenIn != address(IERC20(token0)) && tokenIn != address(IERC20(token1))) revert InvalidToken();
        bool isToken0 = tokenIn == address(IERC20(token0));
        IERC20 tokenInContract = isToken0 ? IERC20(token0) : IERC20(token1);
        IERC20 tokenOutContract = isToken0 ? IERC20(token1) : IERC20(token0);
        // Assume tokens have already been transferred in by the router
        uint256 amountInActual = amountIn;
        uint256 amountInWithFee = _handleFeesAndReturnNetIn(amountInActual, recipient);
        uint256 reserveIn = isToken0 ? _reserve0 : _reserve1;
        uint256 reserveOut = isToken0 ? _reserve1 : _reserve0;
        amountOut = getAmountOut(amountInWithFee, reserveIn, reserveOut);
        if (amountOut < minAmountOut) revert SlippageTooHigh();
        _doTransferOut(tokenOutContract, recipient, amountOut);
        updatePriceOracle();
        _emitSwap(recipient, amountInActual, amountOut, tokenIn, address(tokenOutContract));
    }

    function publicSwap(
        uint256 amountIn,
        address tokenIn,
        uint256 minAmountOut,
        address recipient
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        return _swap(amountIn, tokenIn, minAmountOut, recipient);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure override returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 numerator = amountIn * reserveOut;
        uint256 denominator = reserveIn + amountIn;
        if (denominator == 0) revert DivisionByZero();
        return numerator / denominator;
    }

    function sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        return z;
    }

    function getTwap(string memory denom) public view returns (uint256 price, int64 __lastUpdateTimestamp) {
        ISeiOracle.OracleTwap[] memory twaps = ORACLE.getOracleTwaps(PRICE_LOOKBACK_SECONDS);
        for (uint i = 0; i < twaps.length; i++) {
            if (keccak256(abi.encodePacked(twaps[i].denom)) == keccak256(abi.encodePacked(denom))) {
                price = parseStringToUint(twaps[i].twap);
                __lastUpdateTimestamp = twaps[i].lookbackSeconds;
                return (price, __lastUpdateTimestamp);
            }
        }
        return (0, 0);
    }

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

    // Dynamic TWAP fetcher using mapping
    function getTokenTwap(address token) public view returns (uint256 price, int64 oracleLastUpdate) {
        string memory denom = tokenDenoms[token];
        require(bytes(denom).length > 0, "No denom set");
        (price, oracleLastUpdate) = getTwap(denom);
        require(price > 0, "No price");
        require(block.timestamp - uint64(oracleLastUpdate) <= PRICE_STALENESS_THRESHOLD, "Stale price");
    }

    // Flash loan logic
    function flashLoan(address token, uint256 amount, bytes calldata data) external nonReentrant {
        require(token == address(IERC20(token0)) || token == address(IERC20(token1)), "Invalid token");
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        require(balanceBefore >= amount, "Insufficient liquidity");
        uint256 fee = (amount * flashLoanFeeBps) / 10000;
        IERC20(token).transfer(msg.sender, amount);
        (bool success, ) = msg.sender.call(data);
        require(success, "Callback failed");
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, "Flash loan not repaid");
        emit FlashLoan(msg.sender, token, amount, fee);
    }

    // LPs can claim their rewards
    function claimLPReward() external {
        uint256 reward = lpRewards[msg.sender];
        require(reward > 0, "No reward");
        lpRewards[msg.sender] = 0;
        // Transfer reward in token0 (or choose a reward token logic)
        require(IERC20(token0).transfer(msg.sender, reward), "Reward transfer failed");
        emit LPRewardClaimed(msg.sender, reward);
    }

    // Protocol can claim accrued fees
    function claimProtocolFees() external {
        require(msg.sender == protocolTreasury, "Not treasury");
        uint256 amount = protocolFeesAccrued;
        require(amount > 0, "No fees");
        protocolFeesAccrued = 0;
        require(IERC20(token0).transfer(protocolTreasury, amount), "Transfer failed");
        emit ProtocolFeeClaimed(protocolTreasury, amount);
    }

    // Governance function to set protocol fee and treasury
    function setProtocolFee(uint256 newFeeBps, address newTreasury) external onlyGovernance {
        require(newFeeBps <= 100, "Fee too high");
        require(newTreasury != address(0), "Zero address");
        protocolFeeBps = newFeeBps;
        protocolTreasury = newTreasury;
    }

    // Batch operations
    function batchSwap(uint256[] calldata amountsIn, address[] calldata tokensIn, uint256[] calldata minAmountsOut) external {
        require(amountsIn.length == tokensIn.length && tokensIn.length == minAmountsOut.length, "Length mismatch");
        for (uint256 i = 0; i < amountsIn.length; i++) {
            _swap(amountsIn[i], tokensIn[i], minAmountsOut[i], msg.sender);
        }
        emit BatchSwap(msg.sender, amountsIn.length);
    }
    function batchAddLiquidity(uint256[] calldata amounts0, uint256[] calldata amounts1) external {
        require(amounts0.length == amounts1.length, "Length mismatch");
        for (uint256 i = 0; i < amounts0.length; i++) {
            addLiquidity(amounts0[i], amounts1[i], msg.sender);
        }
        emit BatchAddLiquidity(msg.sender, amounts0.length);
    }
    function batchRemoveLiquidity(uint256[] calldata liquidities) external {
        for (uint256 i = 0; i < liquidities.length; i++) {
            removeLiquidity(liquidities[i]);
        }
        emit BatchRemoveLiquidity(msg.sender, liquidities.length);
    }

    function setGovernance(address newGovernance) public {
        require(governance == address(0) || msg.sender == governance, "Not allowed");
        governance = newGovernance;
    }
}