// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./AMM.sol";

contract BarukAMMFactory {
    address public immutable implementation;
    mapping(address => mapping(address => address)) public getPair;

    constructor(address _implementation) {
        implementation = _implementation;
    }

    function createPair(address token0, address token1) external returns (address pair) {
        require(token0 != token1, "Identical addresses");
        require(token0 != address(0), "Zero address");
        require(getPair[token0][token1] == address(0), "Pair exists");
        pair = Clones.clone(implementation);
        BarukAMM(pair).initialize(token0, token1);
        BarukAMM(pair).setGovernance(msg.sender);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
    }
} 