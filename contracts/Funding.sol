//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/// @title Chain donation contract
/// @author Michal Kazdan

import "hardhat/console.sol";

contract Funding is Ownable, ERC1155Holder, ReentrancyGuard {
    IERC20 usdc;
    IERC20 usdt;

    address[] private tokens;

    error FundInactive(uint256 fund);
    error InvalidAmount(uint256 amount);
    // error InvalidAddress(address addr);
    error RewardFull(uint256 rewardId);
    error LowBalance(uint256 balance);
    error Deadline(bool deadline);

    /// @dev Structs represents core application data, serves as primary database
    /// @notice Main crowdfunding fund
    struct Fund {
        uint256 id;
        address owner;
        uint256 balance;
        uint256 deadline; /// @dev Timespan for crowdfunding to be active
        uint256 state; ///@dev 0=Canceled, 1=Active, 2=Finished
        uint256 level1;
        uint256 usdcBalance;
        uint256 usdtBalance;
        uint256 micros;
        uint256 backerNumber;
    }

    /// @notice Unlimited amount of microfunds could be connect with a main fund
    struct MicroFund {
        uint256 microId;
        address owner;
        uint256 cap;
        uint256 microBalance;
        uint256 fundId;
        uint256 state; ///@dev 0=Canceled, 1=Active, 2=Finished
        uint256 currency;
        ///@notice 0=Eye, 1=USDC, 2=USDT, 3=DAI(descoped)
    }

    /// @dev Struct for direct donations
    struct Donate {
        uint256 id;
        uint256 fundId;
        address backer;
        uint256 amount;
        uint256 state; ///@dev 0=Donated, 1=Distributed, 2=Refunded
        uint256 currency; ///@notice 0=Eye, 1=USDC, 2=USDT, 3=DAI(descoped)
    }

    /// @dev Struct for rewward metadata connected with a fund
    struct RewardPool {
        uint256 rewardId;
        uint256 fundId;
        uint256 totalNumber;
        uint256 actualNumber;
        address owner;
        address contractAddress;
        uint256 erc20amount;
        uint256 nftId;
        uint256 state; ///@dev 1=NFT active, 2=ERC20 Active, 3=Distributed 4=Canceled
    }

    /// @dev Struct for Reward items connected with a reward pool
    struct Reward {
        uint256 rewardId;
        uint256 rewardItemId;
        address receiver;
        uint256 state; ///@dev 1=NFT active, 2=ERC20 Active, 3=Distributed 4=Canceled
    }

    Fund[] public funds;
    MicroFund[] public microFunds;
    Donate[] public donations;
    RewardPool[] public rewards;
    Reward[] public rewardList;

    /// @dev Construcor contains main supported stablecoins for each blockchain, typically USDC and USDT
    constructor(address usdcAddress, address usdtAddress) {
        usdc = IERC20(usdcAddress);
        usdt = IERC20(usdtAddress);
    }

    /// @notice Main function to create crowdfunding project
    function createFund(uint256 _level1) public {
        /// @notice Create a new project to be funded
        /// @param _currency - token address, fund could be created in any token, this will be also required for payments // For now always 0
        /// @param _level1 - 1st (minimum) level of donation accomplishment, same works for all levels.
        uint256 _deadline = block.timestamp + 30 days;
        /// if (msg.sender == address(0)) revert InvalidAddress(msg.sender);
        if (_level1 < 0) revert InvalidAmount(_level1);
        funds.push(
            Fund({
                owner: msg.sender,
                balance: 0,
                id: funds.length,
                state: 1,
                deadline: _deadline,
                level1: _level1,
                usdcBalance: 0,
                usdtBalance: 0,
                micros: 0,
                backerNumber: 0
            })
        );
        emit FundCreated(funds.length);
    }

    /// @notice Function to donate to a project
    function contribute(
        uint256 _amountM,
        uint256 _amountD,
        uint256 _id,
        uint256 _currency,
        uint256 _rewardId
    ) public isDeadlinePassed(_id) {
        /// @param _amountM - amount of tokens to be sent to microfund
        /// @param _amountD - amount of tokens to be direcly donated
        /// @notice User can create microfund and donate at the same time
        if (funds[_id].state != 1) revert FundInactive(_id);
        if (_amountM < 0) revert InvalidAmount(_amountM);
        if (_amountD < 0) revert InvalidAmount(_amountD);
        /// @notice Transfer function stores amount into this contract, both initial donation and microfund
        /// @dev User approval needed before the donation for _amount (FE part)
        /// @dev Currency recognition
        if (_currency == 1) {
            usdc.transferFrom(msg.sender, address(this), _amountD + _amountM);
            funds[_id].usdcBalance += _amountD;
        } else if (_currency == 2) {
            usdt.transferFrom(msg.sender, address(this), _amountD + _amountM);
            funds[_id].usdcBalance += _amountD;
        }
        /// @notice If donated, fund adds balance and related microfunds are involed
        /// @notice Updated the direct donations
        if (_amountD > 0) {
            donations.push(
                Donate({
                    id: donations.length,
                    fundId: _id,
                    backer: msg.sender,
                    amount: _amountD,
                    state: 0,
                    currency: _currency /// TBD flexible in last stage
                })
            );
            funds[_id].backerNumber += 1;
            ///@notice Add total drained amount to the donated event for stats
            uint256 drained = 0;
            drained = drainMicro(_id, _amountD);
            emit Donated(msg.sender, _amountD, _id, _currency, drained);
        }
        /// @notice If microfund created, it is added to the list
        if (_amountM > 0) {
            microFunds.push(
                MicroFund({
                    owner: msg.sender,
                    cap: _amountM,
                    microBalance: 0,
                    microId: microFunds.length,
                    fundId: _id,
                    state: 1,
                    currency: _currency
                })
            );
            funds[_id].micros += 1;
            emit MicroCreated(
                msg.sender,
                _amountM,
                _id,
                _currency,
                microFunds.length
            );
        }
        funds[_id].balance += _amountD;
        rewardCharge(_rewardId);
    }

    ///@notice Helper reward pool function to gather non-token related rewards
    ///@dev Need to create fake fund 0, with fake pool 0, otherwise contribution won't work universally
    function createZeroData() public onlyOwner {
        funds.push(
            Fund({
                owner: address(0),
                balance: 0,
                id: funds.length,
                state: 1,
                deadline: 0,
                level1: 500,
                usdcBalance: 0,
                usdtBalance: 0,
                micros: 0,
                backerNumber: 0
            })
        );
        rewards.push(
            RewardPool({
                rewardId: rewards.length,
                fundId: 0,
                totalNumber: 1000000000000000,
                actualNumber: 0,
                owner: msg.sender,
                contractAddress: address(0),
                erc20amount: 0,
                nftId: 0,
                state: 1
            })
        );
    }

    /// @notice Charge rewards during contribution process
    function rewardCharge(uint256 _rewardId) internal {
        if (rewards[_rewardId].state != 1) revert FundInactive(_rewardId);
        if (rewards[_rewardId].actualNumber >= rewards[_rewardId].totalNumber)
            revert RewardFull(_rewardId);
        rewards[_rewardId].actualNumber += 1;
        rewardList.push(
            Reward({
                rewardItemId: rewardList.length,
                rewardId: rewards[_rewardId].rewardId,
                receiver: msg.sender,
                state: 1
            })
        );
        if (rewards[_rewardId].actualNumber == rewards[_rewardId].totalNumber) {
            rewards[_rewardId].state = 5; ///@dev Reward list is full
        }
    }

    /// @notice If microfunds are deployed on project, contribution function will drain them
    function drainMicro(uint256 _id, uint256 _amount)
        internal
        returns (uint256)
    {
        /// @notice Find all active microfunds related to the main fund and join the chain donation
        uint256 totalDrained = 0;
        for (uint256 i = 0; i < microFunds.length; i++) {
            if (
                microFunds[i].cap - microFunds[i].microBalance >= _amount &&
                microFunds[i].fundId == _id &&
                microFunds[i].state == 1
            ) {
                microFunds[i].microBalance += _amount;
                funds[_id].balance += _amount;
                totalDrained += _amount;
                if (microFunds[i].currency == 1) {
                    funds[_id].usdcBalance += _amount;
                } else if (microFunds[i].currency == 2) {
                    funds[_id].usdtBalance += _amount;
                }
                /// @notice Close microfund if it reaches its cap
                if (microFunds[i].cap == microFunds[i].microBalance) {
                    microFunds[i].state = 2;
                    emit MicroClosed(
                        microFunds[i].owner,
                        microFunds[i].cap,
                        microFunds[i].fundId
                    );
                }
                emit MicroDrained(microFunds[i].owner, _amount, _id);
            }
        }
        return totalDrained;
    }

    ///@notice Lock tokens as crowdfunding reward - ERC20/ERC1155
    ///@notice One project could have multiple rewards
    function createReward(
        uint256 _fundId,
        uint256 _totalNumber,
        uint256 _rewardAmount,
        address _tokenAddress,
        uint256 _type
    ) public {
        if (_rewardAmount < 0) revert InvalidAmount(_rewardAmount);
        // if (msg.sender == address(0)) revert InvalidAddress(msg.sender);
        if (_type == 0) {
            rewards.push(
                RewardPool({
                    rewardId: rewards.length,
                    fundId: _fundId,
                    totalNumber: _totalNumber,
                    actualNumber: _totalNumber,
                    owner: msg.sender,
                    contractAddress: _tokenAddress, ///@dev Needed zero address to be filled on FE
                    nftId: 0,
                    erc20amount: 0,
                    state: 0 ////@dev 0=Basic actuve 1=NFT active, 2=ERC20 Active, 3=Distributed 4=Canceled
                })
            );
        } else if (_type == 1) {
            IERC20 rewardToken = IERC20(_tokenAddress);
            uint256 bal = rewardToken.balanceOf(msg.sender);
            if (bal < _rewardAmount) revert LowBalance(bal);
            rewardToken.transferFrom(msg.sender, address(this), _rewardAmount);
            rewards.push(
                RewardPool({
                    rewardId: rewards.length,
                    fundId: _fundId,
                    totalNumber: _totalNumber,
                    actualNumber: _totalNumber,
                    owner: msg.sender,
                    contractAddress: _tokenAddress,
                    nftId: 0,
                    erc20amount: _rewardAmount,
                    state: 2 ////@dev 0=Basic actuve 1=NFT active, 2=ERC20 Active, 3=Distributed 4=Canceled
                })
            );
        } else if (_type == 2) {
            if (_totalNumber <= 0) revert InvalidAmount(_totalNumber);
            IERC1155 rewardNft = IERC1155(_tokenAddress);
            //   uint256 bal = rewardNft.balanceOf(msg.sender, _rewardAmount);
            //   require(_totalNumber <= bal, "Not enough token in wallet");
            rewardNft.safeTransferFrom(
                msg.sender,
                address(this),
                _rewardAmount,
                _totalNumber,
                ""
            );
            rewards.push(
                RewardPool({
                    rewardId: rewards.length,
                    fundId: _fundId,
                    totalNumber: _totalNumber,
                    actualNumber: _totalNumber,
                    owner: msg.sender,
                    contractAddress: _tokenAddress,
                    nftId: _rewardAmount,
                    erc20amount: 0,
                    state: 1 ///@dev 1=NFT active, 2=ERC20 Active, 3=Distributed 4=Canceled
                })
            );
        }
        emit RewardCreated(
            rewards.length,
            msg.sender,
            _tokenAddress,
            _rewardAmount,
            _fundId,
            _type
        );
    }

    // Saving space -> will be implemented after diamond
    // function batchDistribute(IERC20 _rewardTokenAddress) public onlyOwner nonReentrant {
    //     for (uint256 i = 0; i < funds.length; i++) {
    //         /// @notice - Only active funds with achieved minimum are eligible for distribution
    //         /// @notice - Function for automation, checks deadline and handles distribution/cancellation
    //         if (block.timestamp < funds[i].deadline) {
    //             continue;
    //         }
    //         /// @notice - Fund accomplished minimum goal
    //         if (
    //             funds[i].state == 1 &&
    //             funds[i].balance >= funds[i].level1 &&
    //             block.timestamp > funds[i].deadline
    //         ) {
    //             distribute(i);
    //         }
    //         /// @notice - If not accomplished, funds are returned back to the users on home chain
    //         else if (
    //             funds[i].state == 1 &&
    //             funds[i].balance < funds[i].level1 &&
    //             block.timestamp > funds[i].deadline
    //         ) {
    //             cancelFund(i);
    //         }
    //     }
    // }

    /// @notice Distributes resources to the owner upon successful funding campaign
    /// @notice All related microfunds, and fund are closed
    /// @notice Check all supported currencies and distribute them to the project owner
    function distribute(uint256 _id) public nonReentrant onlyOwner {
        ///@dev TBD add requirements - deadline reached + amount reached...now left for testing purposes
        ///@dev currently done manually - need batch for automation
        if (funds[_id].state != 1) revert FundInactive(_id);
        if (funds[_id].balance <= 0) revert LowBalance(funds[_id].balance);
        funds[_id].balance = 0;
        funds[_id].state = 2;
        if (funds[_id].usdcBalance > 0) {
            distributeUni(_id, funds[_id].usdcBalance, 1, usdc);
            funds[_id].usdcBalance = 0;
        } else if (funds[_id].usdtBalance > 0) {
            distributeUni(_id, funds[_id].usdtBalance, 2, usdt);
            funds[_id].usdtBalance = 0;
        }
        /// @notice Distribute token reward to eligible users
        for (uint256 i = 0; i < rewards.length; i++) {
            IERC20 rewardToken = IERC20(rewards[i].contractAddress);
            IERC1155 rewardNft = IERC1155(rewards[i].contractAddress);
            if (rewards[i].fundId == _id) {
                rewards[i].state = 3;
                for (uint256 j = 0; j < rewardList.length; j++) {
                    ///@notice - Check NFT rewards
                    if (
                        rewardList[j].rewardId == rewards[i].rewardId &&
                        rewards[i].state == 1
                    ) {
                        rewardNft.setApprovalForAll(
                            rewardList[i].receiver,
                            true
                        );
                        rewardNft.safeTransferFrom(
                            address(this),
                            rewardList[j].receiver,
                            rewards[i].nftId,
                            1,
                            ""
                        );
                        emit NftReward(
                            rewardList[j].receiver,
                            rewards[i].contractAddress,
                            rewards[i].fundId
                        );
                    }
                    ///@notice - Check ERC20 rewards
                    else if (
                        rewardList[j].rewardId == rewards[i].rewardId &&
                        rewards[i].state == 2
                    ) {
                        rewardToken.approve(
                            rewardList[i].receiver,
                            rewards[i].erc20amount
                        );
                        rewardToken.transferFrom(
                            address(this),
                            rewardList[j].receiver,
                            rewards[i].erc20amount
                        );
                        emit TokenReward(
                            rewardList[j].receiver,
                            rewards[i].erc20amount,
                            rewards[i].fundId
                        );
                    }
                }
                if (rewards[i].totalNumber > rewards[i].actualNumber) {
                    uint256 rewardsDiff = rewards[i].totalNumber -
                        rewards[i].actualNumber;
                    if (rewards[i].state == 1) {
                        rewardNft.setApprovalForAll(rewards[i].owner, true);
                        rewardNft.safeTransferFrom(
                            address(this),
                            rewards[i].owner,
                            rewards[i].nftId,
                            rewardsDiff,
                            ""
                        );
                    } else if (rewards[i].state == 2) {
                        rewardToken.approve(
                            rewards[i].owner,
                            rewards[i].erc20amount
                        );
                        rewardToken.transferFrom(
                            address(this),
                            rewards[i].owner,
                            (rewards[i].erc20amount / rewards[i].totalNumber) *
                                rewardsDiff
                        );
                    }
                }
            }
        }
    }

    /// @notice Internal universal function to distribute resources for each currency
    function distributeUni(
        uint256 _id,
        uint256 _fundBalance,
        uint256 _currency,
        IERC20 _token
    ) internal {
        /// @notice Take 1% fee to Eyeseek treasury, if amount <100 tak 0%
        address feeAddress = 0xc21223249CA28397B4B6541dfFaEcC539BfF0c59; /// TBD - change to DAO address
        uint256 fee = (_fundBalance * 1) / 100;
        uint256 gain = _fundBalance - fee;
        _token.approve(address(this), _fundBalance);
        _token.transferFrom(address(this), feeAddress, fee);
        _token.transferFrom(address(this), funds[_id].owner, gain);
        emit DistributionAccomplished(
            funds[_id].owner,
            _fundBalance,
            _currency,
            fee
        );
        /// @notice Resources are returned back to the microfunds
        for (uint256 i = 0; i < microFunds.length; i++) {
            if (
                microFunds[i].fundId == _id &&
                microFunds[i].state == 1 &&
                microFunds[i].currency == _currency
            ) {
                if (microFunds[i].cap > microFunds[i].microBalance) {
                    microFunds[i].state = 2; ///@dev closing the microfunds
                    uint256 diff = microFunds[i].cap -
                        microFunds[i].microBalance;
                    _token.approve(address(this), diff);
                    microFunds[i].microBalance = 0; ///@dev resets the microfund
                    _token.transferFrom(
                        address(this),
                        microFunds[_id].owner,
                        diff
                    );
                    emit Returned(microFunds[i].owner, diff, funds[_id].owner);
                }
            }
        }
    }

    ///@notice - Checks balances for each supported currency and returns funds back to the users
    ///@dev 0=Canceled, 1=Active, 2=Finished
    function cancelFund(uint256 _id) public nonReentrant onlyOwner {
        if (funds[_id].state != 1) revert FundInactive(_id);
        funds[_id].state = 0;
        if (funds[_id].usdcBalance > 0) {
            cancelUni(_id, funds[_id].usdcBalance, 1, usdc);
            funds[_id].usdcBalance = 0;
        }
        if (funds[_id].usdtBalance > 0) {
            cancelUni(_id, funds[_id].usdtBalance, 2, usdt);
            funds[_id].usdtBalance = 0;
        }

        for (uint256 i = 0; i < rewards.length; i++) {
            if (
                rewards[i].totalNumber > 0 &&
                rewards[i].fundId == _id &&
                rewards[i].state == 2
            ) {
                IERC1155 rewardNft = IERC1155(rewards[i].contractAddress);
                rewardNft.setApprovalForAll(funds[_id].owner, true);
                rewardNft.safeTransferFrom(
                    address(this),
                    funds[_id].owner,
                    rewards[i].nftId,
                    rewards[i].totalNumber,
                    ""
                );
            } else if (
                rewards[i].totalNumber > 0 &&
                rewards[i].state == 1 &&
                rewards[i].fundId == _id
            ) {
                /// TBD rewards[i].fundId throws error
                console.log(rewards[i].fundId);
                IERC20 rewardToken = IERC20(rewards[i].contractAddress);
                console.log("done erc");
                console.log(rewards[i].erc20amount);
                rewardToken.approve(funds[_id].owner, rewards[i].erc20amount);
                console.log("Approved");
                rewardToken.transferFrom(
                    address(this),
                    funds[_id].owner,
                    rewards[i].erc20amount
                );
            }
        }
    }

    ///@notice - Cancel the fund and return the resources to the microfunds, universal for all supported currencies
    function cancelUni(
        uint256 _id,
        uint256 _fundBalance,
        uint256 _currency,
        IERC20 _token
    ) internal {
        for (uint256 i = 0; i < microFunds.length; i++) {
            if (
                microFunds[i].fundId == _id &&
                microFunds[i].state == 1 &&
                microFunds[i].currency == _currency
            ) {
                /// @notice Send back the remaining amount to the microfund owner
                if (microFunds[i].cap > microFunds[i].microBalance) {
                    microFunds[i].state = 4;
                    funds[_id].balance -= microFunds[i].microBalance;
                    _fundBalance -= microFunds[i].microBalance;
                    _token.approve(address(this), microFunds[i].cap);
                    _token.transferFrom(
                        address(this),
                        microFunds[i].owner,
                        microFunds[i].cap
                    );

                    emit Returned(
                        microFunds[i].owner,
                        microFunds[i].cap,
                        funds[i].owner
                    );
                }
            }
        }
        ///@dev Fund states - 0=Created, 1=Distributed, 2=Refunded
        for (uint256 i = 0; i < donations.length; i++) {
            if (
                donations[i].fundId == _id &&
                donations[i].state == 0 &&
                donations[i].currency == _currency
            ) {
                funds[_id].balance -= donations[i].amount;
                _fundBalance -= donations[i].amount;
                donations[i].state = 4;
                _token.approve(address(this), donations[i].amount);
                _token.transferFrom(
                    address(this),
                    donations[i].backer,
                    donations[i].amount
                );
                emit Refunded(donations[i].backer, donations[i].amount, _id);
            }
        }
    }

    // ------ VIEW FUNCTIONS ----------

    /// @notice - Get total number of microfunds connected to the ID of fund
    function getConnectedMicroFunds(uint256 _index)
        public
        view
        returns (uint256)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < microFunds.length; i++) {
            if (microFunds[i].fundId == _index) {
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
        for (uint256 i = 0; i < microFunds.length; i++) {
            if (
                microFunds[i].fundId == _index &&
                microFunds[i].state == 1 &&
                microFunds[i].cap - microFunds[i].microBalance >= _amount
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
        for (uint256 i = 0; i < microFunds.length; i++) {
            if (
                microFunds[i].fundId == _index &&
                microFunds[i].state == 1 &&
                microFunds[i].cap - microFunds[i].microBalance >= _amount
            ) {
                microNumber++;
            }
        }
        return microNumber;
    }

    // function getRewardReceivers(uint256 _id) public view returns (address[] memory)
    //     {
    //         address[] memory rewardReceivers = new address[](funding.getEligibleRewards(_id));
    //         uint256 rewardNumber = 0;
    //         // for (uint256 i = 0; i < funding.rewardList.length; i++) {
    //         //     if (
    //         //         funding.rewardList[i].rewardId == _index
    //         //     ) {
    //         //         rewardReceivers[rewardNumber] = funding.rewardList[i].receiver;
    //         //         rewardNumber++;
    //         //     }
    //         // }
    //         return rewardReceivers;
    //     }

    ///@notice list of backer addresses for specific fund
    function getBackerAddresses(uint256 _id)
        public
        view
        returns (address[] memory)
    {
        address[] memory backerAddresses;
        uint256 b = funds[_id].backerNumber;

        uint256 number = 0;
        for (uint256 i = 0; i < b; i++) {
            if (donations[i].fundId == _id) {
                backerAddresses[number] = donations[i].backer;
                number++;
            }
        }
        unchecked {
            return backerAddresses;
        }
    }

    // function getEligibleRewards(uint256 _index) public view returns (uint256) {
    //     uint256 rewardNumber = 0;
    //     for (uint256 i = 0; i < rewards.length; i++) {
    //         if (
    //             rewards[i].fundId == _index &&
    //             rewards[i].state == 0
    //         ) {
    //             rewardNumber++;
    //         }
    //     }
    //     return rewardNumber;
    // }

    /// @notice Use modifiers to check when deadline is passed
    modifier isDeadlinePassed(uint256 _id) {
        if (block.timestamp > funds[_id].deadline) {
            revert Deadline(true);
        }
        _;
    }

    event FundCreated(uint256 id);
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
    event DistributionAccomplished(
        address owner,
        uint256 balance,
        uint256 currency,
        uint256 fee
    );
    event Refunded(address backer, uint256 amount, uint256 fundId);
    event RewardCreated(
        uint256 rewardId,
        address owner,
        address contractAddress,
        uint256 amount,
        uint256 fundId,
        uint256 rewardType
    );
    event TokenReward(address backer, uint256 amount, uint256 fundId);
    event NftReward(address backer, address contractAddress, uint256 fundId);
    event Returned(address microOwner, uint256 balance, address fundOwner);
}
