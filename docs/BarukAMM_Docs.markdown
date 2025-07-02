# 🎨 BARUK AUTOMATED MARKET MAKER

> **Info:** Baruk AMM is a smart contract for decentralized token swaps and liquidity provision on Sei Network.  
> **Formula:** `x * y = k` &nbsp; | &nbsp; **Fee:** 0.3% &nbsp; | &nbsp; **Optimized for:** 🚄 High-throughput, low-fee

---

## 🌟 Overview

The Baruk Automated Market Maker (AMM) is a smart contract deployed on the Sei Network's EVM-compatible blockchain, enabling decentralized token swaps and liquidity provision for a single token pair (e.g., SEI/BRK). It uses the constant product formula (`x * y = k`) with a 0.3% swap fee, optimized for Sei's high-throughput, low-fee environment. Built for the Baruk hackathon project, it emphasizes security, gas efficiency, and modularity.

> **Tip:**
> - 🔄 Token Swaps: Swap tokens (e.g., SEI ↔ BRK) with a 0.3% fee for liquidity providers.
> - 💧 Liquidity Management: Add or remove liquidity with proportional token deposits/withdrawals.
> - ⚖️ Constant Product Formula: Ensures price stability using `x * y = k`.
> - 🛡️ Security: Includes reentrancy protection and Solidity's native overflow checks.
> - ⚡ Sei Optimization: Leverages Sei's low gas fees and parallelized EVM.

---

## 📄 Contract Details

| Contract Name | Interface | Solidity Version | License | Deployment Environment |
|--------------|-----------|------------------|---------|-----------------------|
| `BarukAMM.sol` | `IBarukAMM.sol` | `^0.8.19` | MIT | Sei Network ([Testnet RPC](https://evm-rpc-testnet.sei.io)) |

**Dependencies:**
- OpenZeppelin: `IERC20` for token interactions, `ReentrancyGuard` for security.
- Custom: `IBarukAMM` interface for modularity.

---

## 🏦 State Variables

| Name                | Type                                   | Description                                 |
|---------------------|----------------------------------------|---------------------------------------------|
| `token0`            | `IERC20` (private)                     | First token in the pair (e.g., SEI)         |
| `token1`            | `IERC20` (private)                     | Second token in the pair (e.g., BRK)        |
| `factory`           | `address` (public)                     | Address of the factory contract             |
| `reserve0`          | `uint256` (public)                     | Reserve of `token0`                         |
| `reserve1`          | `uint256` (public)                     | Reserve of `token1`                         |
| `totalLiquidity`    | `uint256` (public)                     | Total liquidity tokens issued               |
| `liquidityBalance`  | `mapping(address => uint256)` (public) | Liquidity tokens per user                   |
| `FEE`               | `uint256` (private, constant)          | 0.3% fee (30 basis points)                  |
| `MINIMUM_LIQUIDITY` | `uint256` (private, constant)          | 1000, to prevent division by zero           |

---

## ❗ Custom Errors

> **Warning:**
> - `ArithmeticOverflow(string operation)`: Reverts on arithmetic overflow/underflow.
> - `DivisionByZero()`: Reverts on division by zero.
> - `InvalidToken()`: Reverts if an invalid token address is provided.
> - `InsufficientLiquidity()`: Reverts for zero or insufficient liquidity.
> - `SlippageTooHigh()`: Reverts if swap output is below the minimum specified.
> - `TransferFailed()`: Reverts if token transfers fail.

---

## 🧩 Functions

### 🏗️ constructor

```solidity
constructor(address _token0, address _token1)
```

> Initializes the AMM pool with a token pair.
> - **Parameters:**
>   - `_token0` (`address`): Address of the first token (e.g., SEI).
>   - `_token1` (`address`): Address of the second token (e.g., BRK).
> - **Behavior:** Sets `factory` to `msg.sender`, initializes `token0` and `token1` as `IERC20` contracts.
> - **Access:** Public (called by factory).

---

### 🪙 token0

```solidity
function token0() external view returns (address)
```

> Returns the address of the first token.

---

### 🪙 token1

```solidity
function token1() external view returns (address)
```

> Returns the address of the second token.

---

### ➕ addLiquidity

```solidity
function addLiquidity(uint256 amount0, uint256 amount1) external nonReentrant returns (uint256 liquidity)
```

> Adds liquidity to the pool, minting liquidity tokens for the provider.
> - For initial deposits, mints `sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY` tokens.
> - For subsequent deposits, maintains the pool's token ratio.
> - Transfers tokens from the user to the contract.
> - Updates reserves and liquidity balances.
> - **Requirements:**
>   - `amount0` and `amount1` must be non-zero.
>   - `amount1` must match the pool's ratio for non-initial deposits.
>   - Token transfers must succeed.
> - **Emits:** `LiquidityAdded(address provider, uint256 amount0, uint256 amount1, uint256 liquidity)`

---

### ➖ removeLiquidity

```solidity
function removeLiquidity(uint256 liquidity) external nonReentrant returns (uint256 amount0, uint256 amount1)
```

> Removes liquidity, burning liquidity tokens and returning proportional tokens.
> - Calculates token amounts based on the share of reserves.
> - Burns liquidity tokens and updates reserves.
> - Transfers tokens to the user.
> - **Requirements:**
>   - `liquidity` must be non-zero and within the user's balance.
>   - Token transfers must succeed.
> - **Emits:** `LiquidityRemoved(address provider, uint256 amount0, uint256 amount1, uint256 liquidity)`

---

### 🔄 swap

```solidity
function swap(uint256 amountIn, address tokenIn, uint256 minAmountOut) external nonReentrant returns (uint256 amountOut)
```

> Swaps one token for another, applying a 0.3% fee.
> - Calculates output using the constant product formula (`x * y = k`).
> - Applies a 0.3% fee to `amountIn`.
> - Transfers input tokens to the contract and output tokens to the user.
> - Updates reserves.
> - **Requirements:**
>   - `amountIn` must be non-zero.
>   - `tokenIn` must be `token0` or `token1`.
>   - `amountOut` must meet `minAmountOut`.
>   - Token transfers must succeed.
> - **Emits:** `Swap(address user, uint256 amountIn, uint256 amountOut, address tokenIn)`

---

### 🧮 getAmountOut

```solidity
function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256)
```

> Calculates the output amount for a given input using the constant product formula.
> - Uses the formula `(amountIn * reserveOut) / (reserveIn + amountIn)`.
> - **Requirements:**
>   - `amountIn`, `reserveIn`, and `reserveOut` must be non-zero.
>   - Division by zero must not occur.

---

### 📊 getReserves

```solidity
function getReserves() external view returns (uint256 _reserve0, uint256 _reserve1)
```

> Returns the current reserves of the token pair.

---

## 📢 Events

> **Note:**
> - **LiquidityAdded**
>   ```solidity
>   event LiquidityAdded(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
>   ```
>   Emitted when liquidity is added, logging the provider, token amounts, and liquidity tokens minted.
>
> - **LiquidityRemoved**
>   ```solidity
>   event LiquidityRemoved(address indexed provider, uint256 amount0, uint256 amount1, uint256 liquidity);
>   ```
>   Emitted when liquidity is removed, logging the provider, token amounts, and liquidity tokens burned.
>
> - **Swap**
>   ```solidity
>   event Swap(address indexed user, uint256 amountIn, uint256 amountOut, address tokenIn);
>   ```
>   Emitted when a swap occurs, logging the user, input/output amounts, and input token.
