// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockERC20TransferFromFail is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Simulate non-compliant ERC20: do not return a value (revert in EVM context)
        super.transferFrom(from, to, amount);
        assembly {
            return(0, 0)
        }
    }
} 