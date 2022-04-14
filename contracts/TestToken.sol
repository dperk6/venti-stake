// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor (uint256 initialSupply) ERC20(
        "TEST TOKEN", "TST"
    ) {
        _mint(msg.sender, initialSupply);
    }
}