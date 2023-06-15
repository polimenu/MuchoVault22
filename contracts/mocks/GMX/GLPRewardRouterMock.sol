// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../../interfaces/GMX/IRewardRouter.sol";
import "../../../interfaces/GMX/IGLPPriceFeed.sol";
import "../../../interfaces/IMuchoToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract GLPRewardRouterMock is IRewardRouter { 

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    int256 apr;
    uint256 lastClaim;
    IERC20 glp;
    IMuchoToken weth; //we use this interface as it is mintable
    IGLPPriceFeed priceFeed;


    constructor(IERC20 _glp, IGLPPriceFeed _pFeed, IMuchoToken _weth){
        glp = _glp;
        priceFeed = _pFeed;
        weth = _weth;
    }

    function resetCounter() public{
        lastClaim = block.timestamp;
    }

    function setApr(int256 _apr) external{
        apr = _apr;
    }

    function claimFees() external{
        uint256 timeDiff = block.timestamp.sub(lastClaim);
        resetCounter();

        uint256 usdValue;
        
        if(apr > 0){
            usdValue = glp.balanceOf(msg.sender).mul(uint256(apr).add(10000)).mul(timeDiff).mul(priceFeed.getGLPprice()).div(10**30).div(10000).div(365 days);
        }
        else{
            usdValue = glp.balanceOf(msg.sender).mul(uint256(10000).sub(uint256(-apr))).mul(timeDiff).mul(priceFeed.getGLPprice()).div(10**30).div(10000).div(365 days);
        }

        //uint256 
        uint256 wethAmount = usdValue.mul(10**30).div(priceFeed.getPrice(address(weth)));
        weth.mint(msg.sender, wethAmount);
    }

    function claimEsGmx() external{

    }

    function stakeEsGmx(uint256 _amount) external{

    }
}