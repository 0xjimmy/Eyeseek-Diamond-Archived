// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import "../AppStorage.sol";
import "../Errors.sol";

import "hardhat/console.sol";

contract MasterFacet {
    AppStorage internal s;

    event MicroCreated(
        address owner,
        uint256 cap,
        uint256 fundId,
        uint256 currency,
        uint256 microId
    );
    event Donated(
        address donator,
        uint256 amount,
        uint256 fundId,
        uint256 currency,
        uint256 microDrained
    );
    event MicroDrained(address owner, uint256 amount, uint256 fundId);
    event MicroClosed(address owner, uint256 cap, uint256 fundId);

    /// @notice Use modifiers to check when deadline is passed
    modifier isDeadlinePassed(uint256 _id) {
        if (block.timestamp > s.funds[_id].deadline) {
            revert Deadline(true);
        }
        _;
    }

    /// @notice Function to donate to a project
    function contribute(
        uint256 _amountM,
        uint256 _amountD,
        uint256 _id,
        uint256 _currency,
        uint256 _rewardId
    ) public isDeadlinePassed(_id) {
        /*
        /// @param _amountM - amount of tokens to be sent to microfund
        /// @param _amountD - amount of tokens to be direcly donated
        /// @notice User can create microfund and donate at the same time
        if (s.funds[_id].state != 1) revert FundInactive(_id);
        if (_amountM < 0) revert InvalidAmount(_amountM);
        if (_amountD < 0) revert InvalidAmount(_amountD);
        /// @notice Transfer function stores amount into this contract, both initial donation and microfund
        /// @dev User approval needed before the donation for _amount (FE part)
        /// @dev Currency recognition
        if (_currency == 1) {
            s.usdc.transferFrom(msg.sender, address(this), _amountD + _amountM);
            s.funds[_id].usdcBalance += _amountD;
        } else if (_currency == 2) {
            s.usdt.transferFrom(msg.sender, address(this), _amountD + _amountM);
            s.funds[_id].usdcBalance += _amountD;
        }
        /// @notice If donated, fund adds balance and related microfunds are involed
        /// @notice Updated the direct donations
        if (_amountD > 0) {
            s.donations.push(
                Donate({
                    id: s.donations.length,
                    fundId: _id,
                    backer: msg.sender,
                    amount: _amountD,
                    state: 0,
                    currency: _currency /// TBD flexible in last stage
                })
            );
            s.funds[_id].backerNumber += 1;
            ///@notice Add total drained amount to the donated event for stats
            uint256 drained = 0;
            drained = drainMicro(_id, _amountD);
            emit Donated(msg.sender, _amountD, _id, _currency, drained);
        }
        /// @notice If microfund created, it is added to the list
        if (_amountM > 0) {
            s.microFunds.push(
                MicroFund({
                    owner: msg.sender,
                    cap: _amountM,
                    microBalance: 0,
                    microId: s.microFunds.length,
                    fundId: _id,
                    state: 1,
                    currency: _currency
                })
            );
            s.funds[_id].micros += 1;
            emit MicroCreated(
                msg.sender,
                _amountM,
                _id,
                _currency,
                s.microFunds.length
            );
        }
        s.funds[_id].balance += _amountD;
        rewardCharge(_rewardId);
        */
    }

    /// @notice Charge rewards during contribution process
    function rewardCharge(uint256 _rewardId) internal {
        if (s.rewards[_rewardId].state != 1) revert FundInactive(_rewardId);
        if (
            s.rewards[_rewardId].actualNumber >=
            s.rewards[_rewardId].totalNumber
        ) revert RewardFull(_rewardId);
        s.rewards[_rewardId].actualNumber += 1;
        s.rewardList.push(
            Reward({
                rewardItemId: s.rewardList.length,
                rewardId: s.rewards[_rewardId].rewardId,
                receiver: msg.sender,
                state: 1
            })
        );
        if (
            s.rewards[_rewardId].actualNumber ==
            s.rewards[_rewardId].totalNumber
        ) {
            s.rewards[_rewardId].state = 5; ///@dev Reward list is full
        }
    }

    /// @notice If microfunds are deployed on project, contribution function will drain them
    function drainMicro(uint256 _id, uint256 _amount)
        internal
        returns (uint256)
    {
        /// @notice Find all active microfunds related to the main fund and join the chain donation
        uint256 totalDrained = 0;
        for (uint256 i = 0; i < s.microFunds.length; i++) {
            if (
                s.microFunds[i].cap - s.microFunds[i].microBalance >= _amount &&
                s.microFunds[i].fundId == _id &&
                s.microFunds[i].state == 1
            ) {
                s.microFunds[i].microBalance += _amount;
                s.funds[_id].balance += _amount;
                totalDrained += _amount;
                if (s.microFunds[i].currency == 1) {
                    s.funds[_id].usdcBalance += _amount;
                } else if (s.microFunds[i].currency == 2) {
                    s.funds[_id].usdtBalance += _amount;
                }
                /// @notice Close microfund if it reaches its cap
                if (s.microFunds[i].cap == s.microFunds[i].microBalance) {
                    s.microFunds[i].state = 2;
                    emit MicroClosed(
                        s.microFunds[i].owner,
                        s.microFunds[i].cap,
                        s.microFunds[i].fundId
                    );
                }
                emit MicroDrained(s.microFunds[i].owner, _amount, _id);
            }
        }
        return totalDrained;
    }
}
