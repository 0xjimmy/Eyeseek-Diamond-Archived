// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20 {
    constructor() ERC20("Eye USDC", "USDC") {
        _mint(msg.sender, 5000000000 * 10 ** decimals());
    }
}