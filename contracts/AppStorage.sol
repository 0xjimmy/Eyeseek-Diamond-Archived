// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

struct AppStorage {
    uint256 _reentracyStatus;
    IERC20 usdc;
    IERC20 usdt;
    address[] tokens;
    Fund[] funds;
    MicroFund[] microFunds;
    Donate[] donations;
    RewardPool[] rewards;
    Reward[] rewardList;
}

library LibAppStorage {
    function diamondStorage() internal pure returns (AppStorage storage ds) {
        assembly {
            ds.slot := 0
        }
    }

    function abs(int256 x) internal pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }
}

contract Modifiers {
    AppStorage internal s;

    modifier nonReentrant() {
        require(s._reentracyStatus != 2, "ReentrancyGuard: reentrant call");
        s._reentracyStatus = 2;

        _;

        s._reentracyStatus = 1;
    }
}
