// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import "../MuchoRoles.sol";
import "../../interfaces/IMuchoProtocol.sol";
import "../../interfaces/GMX/IGLPPriceFeed.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


contract FakeTestMuchoProtocolGMX is MuchoRoles, ReentrancyGuard{

    /*----------------------------SETUP--------------------------------------*/

    //Set parameters:
    function setAprUpdatePeriod(uint256 _seconds) external onlyAdmin{}
    function setSlippage(uint256 _slippage) external onlyOwner{}
    function setMinNotInvestedPercentage(uint256 _percent) external onlyAdmin {}
    function setDesiredNotInvestedPercentage(uint256 _percent) external onlyAdmin {}
    function setMinWeightBasisPointsMove(uint256 _percent) external onlyAdmin {}
    function updateClaimEsGMX(bool _new) external onlyOwner {  }
    function setManualModeWeights(bool _manual) external onlyOwner { }
    function setWeight(address _token, uint256 _percent) external onlyOwner {}
    function setRewardPercentages(RewardSplit calldata _split) onlyTraderOrAdmin external{}

    //Set Token Mocks:
    function updatefsGLP(address _new) external onlyOwner { }
    function updateWETH(address _new) external onlyOwner { }
    function updateEsGMX(address _new) external onlyOwner { }

    //Set GMX contracts Mocks:
    function updateRouter(address _newRouter) external onlyAdmin { }
    function updateRewardRouter(address _newRouter) external onlyAdmin {  } 
    function updateGLPVault(address _newVault) external onlyAdmin {  } 
    function updatepoolGLP(address _newManager) external onlyAdmin {  }  //Mock is the same as glp vault
    function setPriceFeed(IGLPPriceFeed _feed) onlyAdmin external{}

    //Set Mucho contract Mocks:
    function setMuchoRewardRouter(address _contract) onlyAdmin external{}
    function setCompoundProtocol(IMuchoProtocol _target) onlyTraderOrAdmin external{}

    //Secondary tokens:
    function addSecondaryToken(address _mainToken, address _secondary) onlyAdmin external{ }
    function removeSecondaryToken(address _mainToken, address _secondary) onlyAdmin external{}


    /*----------------------------METHODS--------------------------------------*/

    function updateGlpWeights() onlyTraderOrAdmin public{}
    function refreshInvestment() onlyTraderOrAdmin external {}
    function cycleRewards() onlyTraderOrAdmin external{}

    function withdrawAndSend(address _token, uint256 _amount, address _target) onlyOwner nonReentrant external{}
    function notInvestedTrySend(address _token, uint256 _amount, address _target) onlyOwner nonReentrant public returns(uint256){}
    function notifyDeposit(address _token, uint256 _amount) onlyOwner nonReentrant external{}


    /*----------------------------VIEWS--------------------------------------*/

    function getLastPeriodsApr(address _token) external view returns(int256[30] memory){}
    function getTotalInvested(address _token) public view returns(uint256){}
    function getTotalNotInvested(address _token) public view returns(uint256){}
    function getTotalStaked(address _token) public view returns(uint256){}
    function getTotalUSD() public view returns(uint256){}
    function getTotalUSDWithTokensUsd() public view returns(uint256, uint256[] memory){}
    function getTokenTotalUSD(address _token) public  view returns(uint256){}


}