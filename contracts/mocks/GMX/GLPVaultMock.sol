// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;


import "../../../interfaces/GMX/IGLPVault.sol";
import "../../../interfaces/IPriceFeed.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract GLPVaultMock is IGLPVault {

    using SafeMath for uint256;

    IPriceFeed priceFeed;

    constructor(IERC20 _usdc, IERC20 _weth, IERC20 _wbtc, IPriceFeed _pFeed){
        priceFeed = _pFeed;
    }
    
    function taxBasisPoints() external pure returns (uint256){
        return 60;
    }

    function mintBurnFeeBasisPoints() external pure returns (uint256){
        return 25;
    }

    function usdgAmounts(address _token) external view returns (uint256){
        return IERC20(_token).balanceOf(address(this)).mul(priceFeed.getPrice(_token)).div(10**30);
    }

    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) external view returns (uint256){
        //mint fee
        if(_increment) return 25;
        return 30;
    }
}