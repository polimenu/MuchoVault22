// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;


import "../../../interfaces/GMX/IGLPVault.sol";
import "../../../interfaces/IPriceFeed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

contract GLPVaultMock is IGLPVault {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IPriceFeed priceFeed;
    function setPriceFeed(IPriceFeed _pFeed) external{
        priceFeed = _pFeed;
    }

    address router;
    function setRouter(address _rt) external{
        router = _rt;
    }
    
    function allowRouter(address _token, uint256 _amount) external{
        require(msg.sender == router, "No router");
        console.log("Approving spent", router, _token, _amount);
        IERC20(_token).approve(router, _amount);
    }

    function receiveTokenFrom(address _sender, address _token, uint256 _amount) external{
        IERC20(_token).safeTransferFrom(_sender, address(this), _amount);
    }

    constructor(){
    }
    
    function taxBasisPoints() external pure returns (uint256){
        return 60;
    }

    function mintBurnFeeBasisPoints() external pure returns (uint256){
        return 25;
    }

    function usdgAmounts(address _token) external view returns (uint256){
        uint256 decimals = IERC20Metadata(_token).decimals();
        return IERC20(_token).balanceOf(address(this)).mul(priceFeed.getPrice(_token)).div(10**(30-18+decimals));
    }

    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) external view returns (uint256){
        //mint fee
        if(_increment) return 25;
        return 30;
    }
}