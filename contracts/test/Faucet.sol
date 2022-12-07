// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;


interface ERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
}

contract Faucet {
    uint256 constant public tokenAmount = 1000;

    ERC20 public tokenInstance;
    
    mapping(address => uint256) lastAccessTime;

    constructor(address _tokenInstance) {
        tokenInstance = ERC20(_tokenInstance);
    }

    function requestTokens() public {
        uint256 decAmount = tokenAmount * 10 ** 18;
        tokenInstance.transfer(msg.sender, decAmount) ;
        emit FaucetReceived(msg.sender);
    }
    
    event FaucetReceived(address sender);
}