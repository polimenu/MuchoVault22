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

contract MuchoProtocolNoInvestment is IMuchoProtocol, MuchoRoles, ReentrancyGuard{

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    IPriceFeed priceFeed;
    EnumerableSet.AddressSet tokenList;


    function protocolName() public pure returns(string memory){
        return "MuchoProtocolNoInvestment";
    }
    function protocolDescription() public pure returns(string memory){
        return "Stores tokens without investing them";
    }

    function setPriceFeed(IPriceFeed _feed) onlyAdmin external{
        priceFeed = _feed;
    }
    function refreshInvestment() onlyTraderOrAdmin external {}
    function cycleRewards() onlyTraderOrAdmin external{}

    function withdrawAndSend(address _token, uint256 _amount, address _target) onlyOwner external{
        IERC20 tk = IERC20(_token);
        require(tk.balanceOf(address(this)) >= _amount, "MuchoProtocolNoInvestment: not enough balance");
        tk.safeTransfer(_target, _amount);
    }

    function notInvestedTrySend(address _token, uint256 _amount, address _target) onlyOwner external returns(uint256){
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
    function notifyDeposit(address _token, uint256 _amount) onlyOwner external{
        tokenList.add(_token);
    }

    function setRewardPercentages(RewardSplit memory _split) onlyTraderOrAdmin external{}
    function setCompoundProtocol(IMuchoProtocol _target) onlyTraderOrAdmin external{}
    function setMuchoRewardRouter(address _contract) onlyAdmin external{}

    function getLastPeriodsApr(address _token) external view returns(int256[30] memory){
        int256[30] memory apr;
        return apr;
    }
    function getTokenNotInvested(address _token) public view returns(uint256){
        return IERC20(_token).balanceOf(address(this));
    }
    function getTokenStaked(address _token) public view returns(uint256){
        return getTokenNotInvested(_token);
    }

    function getAllTokensStaked() public view returns (address[] memory, uint256[] memory) {
        address[] memory tkOut = new address[](tokenList.length());
        uint256[] memory amOut = new uint256[](tokenList.length());
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            tkOut[i] = tokenList.at(i);
            amOut[i] = getTokenStaked(tkOut[i]);
        }

        return (tkOut, amOut);
    }
    function getTokenInvested(address _token) public view returns(uint256){
        return getTokenStaked(_token).sub(getTokenNotInvested(_token));
    }

    function getTokenUSDInvested(address _token) external pure returns(uint256){
        return 0;
    }
    function getTokenUSDNotInvested(address _token) external view returns(uint256){
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenNotInvested(_token).mul(priceFeed.getPrice(_token)).div(10**(30-18+decimals));
    }
    function getTokenUSDStaked(address _token) external view returns(uint256){
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenStaked(_token).mul(priceFeed.getPrice(_token)).div(10**(30-18+decimals));
    }

    function getTotalUSD() external view returns(uint256){
        uint256 totalUsd = 0;
        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            totalUsd = totalUsd.add(IERC20(tokenList.at(i)).balanceOf(address(this)).mul(priceFeed.getPrice(tokenList.at(i))));
        }
        return totalUsd;
    }
}