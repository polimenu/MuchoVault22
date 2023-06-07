// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../../interfaces/IMuchoProtocol.sol";
import "../../interfaces/IPriceFeed.sol";
import "../../interfaces/IMuchoToken.sol";
import "../../lib/AprInfo.sol";
import "../MuchoRoles.sol";

//import "../../lib/UintSafe.sol";

contract MuchoProtocolMock is IMuchoProtocol {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using AprLib for AprInfo;

    EnumerableSet.AddressSet tokenList;
    int256 apr;
    uint256 lastUpdate;
    AprInfo aprInfo;
    IPriceFeed priceFeed;

    function setPriceFeed(IPriceFeed _feed) external {
        priceFeed = _feed;
    }

    function setApr(int256 _apr) external {
        cycleRewards();
        apr = _apr;
        lastUpdate = block.timestamp;
    }

    function protocolName() public pure returns(string memory){
        return "MuchoProtocolMock";
    }
    function protocolDescription() public pure returns(string memory){
        return "Mock for testing use. Simulates APR by minting fake ERC20 tokens";
    }

    function cycleRewards() public {
        uint256 timeDiff = block.timestamp.sub(lastUpdate);
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            uint256 am = IERC20(tokenList.at(i)).balanceOf(address(this));
            uint256 newAm;

            //Mint or burn new tokens to simulate apr:
            if(apr == 0)
                newAm = am;
            else if(apr > 0){
                newAm = am.add(am.mul(uint256(apr)).mul(timeDiff).div(365 days).div(10000));
                IMuchoToken(tokenList.at(i)).mint(address(this), newAm.sub(am));
            }
            else{
                newAm = am.sub(am.mul(uint256(apr)).mul(timeDiff).div(365 days).div(10000));
                IMuchoToken(tokenList.at(i)).burn(address(this), am.sub(newAm));
            }

        }
        lastUpdate = block.timestamp;
        aprInfo.updateApr(apr);
    }

    function refreshInvestment() external {
        cycleRewards();
    }

    function withdrawAndSend(
        address _token,
        uint256 _amount,
        address _target
    ) external {
        IERC20 tk = IERC20(_token);
        require(
            tk.balanceOf(address(this)) >= _amount,
            "MuchoProtocolMock: not enough balance"
        );
        tk.safeTransfer(_target, _amount);
    }

    function notInvestedTrySend(
        address _token,
        uint256 _amount,
        address _target
    ) external returns (uint256) {
        IERC20 tk = IERC20(_token);
        uint256 balance = tk.balanceOf(address(this));
        if (balance >= _amount) {
            tk.safeTransfer(_target, _amount);
            return _amount;
        } else {
            tk.safeTransfer(_target, balance);
            return balance;
        }
    }

    function notifyDeposit(address _token, uint256 _amount) external {
        tokenList.add(_token);
    }

    function setRewardPercentages(RewardSplit memory _split) external {}

    function setCompoundProtocol(IMuchoProtocol _target) external {}

    function setMuchoRewardRouter(address _contract) external {}

    function getLastPeriodsApr(
        address _token
    ) external view returns (int256[30] memory) {
        return aprInfo.apr;
    }

    function getTotalNotInvested(address _token) public view returns (uint256) {
        return 0;
    }

    function getTotalStaked(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function getTotalUSD() external view returns (uint256) {
        uint256 totalUsd = 0;
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            totalUsd = totalUsd.add(
                IERC20(tokenList.at(i)).balanceOf(address(this)).mul(
                    priceFeed.getPrice(tokenList.at(i))
                )
            );
        }
        return totalUsd;
    }
}
