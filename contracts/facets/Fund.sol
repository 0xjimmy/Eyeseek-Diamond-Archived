// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {LibDiamond} from "../libraries/LibDiamond.sol";
import "../AppStorage.sol";
import "../Errors.sol";

import "hardhat/console.sol";

contract FundFacet is ReentrancyGuard {
    AppStorage internal s;

    event FundCreated(uint256 id);
    event MicroDrained(address owner, uint256 amount, uint256 fundId);
    event MicroClosed(address owner, uint256 cap, uint256 fundId);
    event Refunded(address backer, uint256 amount, uint256 fundId);
    event Returned(address microOwner, uint256 balance, address fundOwner);

    /// @notice Main function to create crowdfunding project
    function createFund(uint256 _level1) public {
        /// @notice Create a new project to be funded
        /// @param _currency - token address, fund could be created in any token, this will be also required for payments // For now always 0
        /// @param _level1 - 1st (minimum) level of donation accomplishment, same works for all levels.
        uint256 _deadline = block.timestamp + 30 days;
        /// if (msg.sender == address(0)) revert InvalidAddress(msg.sender);
        if (_level1 < 0) revert InvalidAmount(_level1);
        s.funds.push(
            Fund({
                owner: msg.sender,
                balance: 0,
                id: s.funds.length,
                state: 1,
                deadline: _deadline,
                level1: _level1,
                usdcBalance: 0,
                usdtBalance: 0,
                micros: 0,
                backerNumber: 0
            })
        );
        emit FundCreated(s.funds.length);
    }

    ///@notice - Checks balances for each supported currency and returns funds back to the users
    ///@dev 0=Canceled, 1=Active, 2=Finished
    function cancelFund(uint256 _id) public nonReentrant {
        LibDiamond.enforceIsContractOwner();

        if (s.funds[_id].state != 1) revert FundInactive(_id);
        s.funds[_id].state = 0;
        if (s.funds[_id].usdcBalance > 0) {
            cancelUni(_id, s.funds[_id].usdcBalance, 1, s.usdc);
            s.funds[_id].usdcBalance = 0;
        }
        if (s.funds[_id].usdtBalance > 0) {
            cancelUni(_id, s.funds[_id].usdtBalance, 2, s.usdt);
            s.funds[_id].usdtBalance = 0;
        }

        for (uint256 i = 0; i < s.rewards.length; i++) {
            if (
                s.rewards[i].totalNumber > 0 &&
                s.rewards[i].fundId == _id &&
                s.rewards[i].state == 2
            ) {
                IERC1155 rewardNft = IERC1155(s.rewards[i].contractAddress);
                rewardNft.setApprovalForAll(s.funds[_id].owner, true);
                rewardNft.safeTransferFrom(
                    address(this),
                    s.funds[_id].owner,
                    s.rewards[i].nftId,
                    s.rewards[i].totalNumber,
                    ""
                );
            } else if (
                s.rewards[i].totalNumber > 0 &&
                s.rewards[i].state == 1 &&
                s.rewards[i].fundId == _id
            ) {
                /// TBD s.rewards[i].fundId throws error
                console.log(s.rewards[i].fundId);
                IERC20 rewardToken = IERC20(s.rewards[i].contractAddress);
                console.log("done erc");
                console.log(s.rewards[i].erc20amount);
                rewardToken.approve(
                    s.funds[_id].owner,
                    s.rewards[i].erc20amount
                );
                console.log("Approved");
                rewardToken.transferFrom(
                    address(this),
                    s.funds[_id].owner,
                    s.rewards[i].erc20amount
                );
            }
        }
    }

    /// @notice - Get total number of microfunds connected to the ID of fund
    function getConnectedMicroFunds(uint256 _index)
        public
        view
        returns (uint256)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < s.microFunds.length; i++) {
            if (s.microFunds[i].fundId == _index) {
                count++;
            }
        }
        return count;
    }

    /// @notice - Calculate amounts of all involved microfunds in the donation
    function calcOutcome(uint256 _index, uint256 _amount)
        public
        view
        returns (uint256)
    {
        uint256 total = 0;
        total += _amount;
        for (uint256 i = 0; i < s.microFunds.length; i++) {
            if (
                s.microFunds[i].fundId == _index &&
                s.microFunds[i].state == 1 &&
                s.microFunds[i].cap - s.microFunds[i].microBalance >= _amount
            ) {
                total += _amount;
            }
        }
        return total;
    }

    /// @notice - Calculate number of involved microfunds for specific donation amount
    function calcInvolvedMicros(uint256 _index, uint256 _amount)
        public
        view
        returns (uint256)
    {
        uint256 microNumber = 0;
        for (uint256 i = 0; i < s.microFunds.length; i++) {
            if (
                s.microFunds[i].fundId == _index &&
                s.microFunds[i].state == 1 &&
                s.microFunds[i].cap - s.microFunds[i].microBalance >= _amount
            ) {
                microNumber++;
            }
        }
        return microNumber;
    }

    ///@notice list of backer addresses for specific fund
    function getBackerAddresses(uint256 _id)
        public
        view
        returns (address[] memory)
    {
        address[] memory backerAddresses;
        uint256 b = s.funds[_id].backerNumber;

        uint256 number = 0;
        for (uint256 i = 0; i < b; i++) {
            if (s.donations[i].fundId == _id) {
                backerAddresses[number] = s.donations[i].backer;
                number++;
            }
        }
        unchecked {
            return backerAddresses;
        }
    }

    ///@notice - Cancel the fund and return the resources to the microfunds, universal for all supported currencies
    function cancelUni(
        uint256 _id,
        uint256 _fundBalance,
        uint256 _currency,
        IERC20 _token
    ) internal {
        for (uint256 i = 0; i < s.microFunds.length; i++) {
            if (
                s.microFunds[i].fundId == _id &&
                s.microFunds[i].state == 1 &&
                s.microFunds[i].currency == _currency
            ) {
                /// @notice Send back the remaining amount to the microfund owner
                if (s.microFunds[i].cap > s.microFunds[i].microBalance) {
                    s.microFunds[i].state = 4;
                    s.funds[_id].balance -= s.microFunds[i].microBalance;
                    _fundBalance -= s.microFunds[i].microBalance;
                    _token.approve(address(this), s.microFunds[i].cap);
                    _token.transferFrom(
                        address(this),
                        s.microFunds[i].owner,
                        s.microFunds[i].cap
                    );

                    emit Returned(
                        s.microFunds[i].owner,
                        s.microFunds[i].cap,
                        s.funds[i].owner
                    );
                }
            }
        }
        ///@dev Fund states - 0=Created, 1=Distributed, 2=Refunded
        for (uint256 i = 0; i < s.donations.length; i++) {
            if (
                s.donations[i].fundId == _id &&
                s.donations[i].state == 0 &&
                s.donations[i].currency == _currency
            ) {
                s.funds[_id].balance -= s.donations[i].amount;
                _fundBalance -= s.donations[i].amount;
                s.donations[i].state = 4;
                _token.approve(address(this), s.donations[i].amount);
                _token.transferFrom(
                    address(this),
                    s.donations[i].backer,
                    s.donations[i].amount
                );
                emit Refunded(
                    s.donations[i].backer,
                    s.donations[i].amount,
                    _id
                );
            }
        }
    }
}
