// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor() ERC20("Eyeseek", "EYE") {
        _mint(msg.sender, 5000000 * 10 ** decimals());
    }
}