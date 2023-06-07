// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../../interfaces/IMuchoProtocol.sol";
import "../../interfaces/IPriceFeed.sol";
import "../MuchoRoles.sol";
//import "../../lib/UintSafe.sol";

contract MuchoProtocolMock is IMuchoProtocol{

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet tokenList;
    uint256 apr;
    uint256 lastUpdate;

    function setApr(uint256 _apr) external{
        cycleRewards();
        apr = _apr;
        lastUpdate = block.timestamp;
    }

    function cycleRewards() public {
        uint256 timeDiff = block.timestamp.sub(lastUpdate);
        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            uint256 am = IERC20(tokenList.at(i)).balanceOf(address(this));
            uint256 newAm = am.mul(apr).mul(timeDiff).div(365 days).div(10000);
            //Mint new tokens to simulate apr:
            IERC20(tokenList.at(i)).mint(address(this), newAm.sub(am));
        }
        lastUpdate = block.timestamp;
    }

    function refreshInvestment() external{
        cycleRewards();
    }

    function withdrawAndSend(address _token, uint256 _amount, address _target) external{
        IERC20 tk = IERC20(_token);
        require(tk.balanceOf(address(this)) >= _amount, "MuchoProtocolMock: not enough balance");
        tk.safeTransfer(_target, _amount);
    }

    function notInvestedTrySend(address _token, uint256 _amount, address _target) external returns(uint256){
        IERC20 tk = IERC20(_token);
        uint256 balance = tk.balanceOf(address(this));
        if(balance >= _amount){
            tk.safeTransfer(_target, _amount);
            return _amount;
        }
        else{
            tk.safeTransfer(_target, balance);
            return balance;
        }
    }
    function notifyDeposit(address _token, uint256 _amount) external{
        tokenList.add(_token);
    }

    function setRewardPercentages(RewardSplit memory _split) onlyTraderOrAdmin external{}
    function setCompoundProtocol(IMuchoProtocol _target) onlyTraderOrAdmin external{}
    function setMuchoRewardRouter(address _contract) onlyAdmin external{}

    function getLastPeriodsApr(address _token) external view returns(int256[30] memory){
        int256[30] memory apr;
        return apr;
    }
    function getTotalNotInvested(address _token) public view returns(uint256){
        return IERC20(_token).balanceOf(address(this));
    }
    function getTotalStaked(address _token) external view returns(uint256){
        return getTotalNotInvested(_token);
    }
    function getTotalUSD() external view returns(uint256){
        uint256 totalUsd = 0;
        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            totalUsd = totalUsd.add(IERC20(tokenList.at(i)).balanceOf(address(this)).mul(priceFeed.getPrice(tokenList.at(i))));
        }
        return totalUsd;
    }
}