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
//import "hardhat/console.sol";
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
    uint256 notInvestedBP;
    mapping(address => uint256) notInvestedAmount;

    constructor(int256 _apr, uint256 _notInvestedBP, IPriceFeed _feed){
        priceFeed = _feed;
        apr = _apr;
        notInvestedBP = _notInvestedBP;
        lastUpdate = block.timestamp;
    }

    function setNotInvestedBP(uint256 _bp) external{
        notInvestedBP = _bp;
    }

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
        return "Mock for testing use. Simulates APR by minting or burning fake ERC20 tokens (needs to be owner of them)";
    }

    function cycleRewards() public {
        uint256 timeDiff = block.timestamp.sub(lastUpdate);
        //console.log("    SOL MuchoProtocolMock - CYCLING REWARDS", timeDiff);
        //console.log("    SOL MuchoProtocolMock - timeDiff", timeDiff);
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            //console.log("    SOL MuchoProtocolMock --------------------------------- i", i);
            uint256 am = IERC20(tokenList.at(i)).balanceOf(address(this)).sub(notInvestedAmount[tokenList.at(i)]);
            uint256 newAm;
            //console.log("    SOL MuchoProtocolMock - am", am);

            //Mint or burn new tokens to simulate apr:
            if(apr == 0){
                //console.log("    SOL MuchoProtocolMock - apr zero");
                newAm = am;
            }
            else if(apr > 0){
                //console.log("    SOL MuchoProtocolMock - POSITIVE apr", uint256(apr));
                newAm = am.add(am.mul(uint256(apr)).mul(timeDiff).div(365 days).div(10000));
                IMuchoToken(tokenList.at(i)).mint(address(this), newAm.sub(am));
            }
            else{
                //console.log("    SOL MuchoProtocolMock - NEGATIVE apr", uint256(-apr));
                newAm = am.sub(am.mul(uint256(-apr)).mul(timeDiff).div(365 days).div(10000));
                IMuchoToken(tokenList.at(i)).burn(address(this), am.sub(newAm));
            }

        }
        lastUpdate = block.timestamp;
        //console.log("    SOL MuchoProtocolMock - Updating APR");
        aprInfo.updateApr(apr * (10000 - int256(notInvestedBP)) / 10000);
    }

    function refreshInvestment() external {
        //
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            notInvestedAmount[tokenList.at(i)] = IERC20(tokenList.at(i)).balanceOf(address(this)).mul(notInvestedBP).div(10000);
        }
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
        uint256 balance = tk.balanceOf(address(this)).mul(notInvestedBP).div(10000);
        uint256 amountToTransfer = (balance >= _amount) ? _amount : balance;

        notInvestedAmount[_token] = notInvestedAmount[_token].sub(amountToTransfer);
        tk.safeTransfer(_target, amountToTransfer);
        return amountToTransfer;
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

    function getTokenNotInvested(address _token) public view returns (uint256) {
        return notInvestedAmount[_token];
    }

    function getTokenInvested(address _token) public view returns (uint256) {
        return getTokenStaked(_token).sub(notInvestedAmount[_token]);
    }

    function getTokenStaked(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function getTokenUSDInvested(address _token) public view returns(uint256){
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenInvested(_token).mul(priceFeed.getPrice(_token)).div(10**(30-18+decimals));
    }
    function getTokenUSDNotInvested(address _token) public view returns(uint256){
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenNotInvested(_token).mul(priceFeed.getPrice(_token)).div(10**(30-18+decimals));
    }
    function getTokenUSDStaked(address _token) public view returns(uint256){
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenStaked(_token).mul(priceFeed.getPrice(_token)).div(10**(30-18+decimals));
    }

    function getTotalUSD() external view returns (uint256) {
        uint256 totalUsd = 0;
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            uint8 decimalsAdjust = 30 - 18 + IERC20Metadata(tokenList.at(i)).decimals();
            totalUsd = totalUsd.add(
                IERC20(tokenList.at(i)).balanceOf(address(this)).mul(
                    priceFeed.getPrice(tokenList.at(i))
                ).div(10**decimalsAdjust)
            );
        }
        return totalUsd;
    }
}
