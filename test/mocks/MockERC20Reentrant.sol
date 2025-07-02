// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Reentrant.sol";

contract MockERC20Reentrant is ERC20Reentrant {
    // // Re-expose the Type enum for test usage
    //  enum Type { No, Before, After }
    // function mint(address to, uint256 amount) external {
    //     _mint(to, amount);
    // }
    // // Expose the Type enum for test usage
    // function typeNo() external pure returns (Type) { return Type.No; }
    // function typeBefore() external pure returns (Type) { return Type.Before; }
    // function typeAfter() external pure returns (Type) { return Type.After; }
} 