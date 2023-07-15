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

    uint256 apr;
    uint256 lastClaim;
    IERC20 glp;
    IMuchoToken weth; //we use this interface as it is mintable
    IGLPPriceFeed priceFeed;


    constructor(IERC20 _glp, IGLPPriceFeed _pFeed, IMuchoToken _weth){
        glp = _glp;
        priceFeed = _pFeed;
        weth = _weth;
        resetCounter();
    }

    function resetCounter() public{
        lastClaim = block.timestamp;
    }

    function setApr(uint256 _apr) external{
        apr = _apr;
    }

    function claimFees() external{
        //console.log("    SOL***claimFees***");
        uint256 timeDiff = block.timestamp.sub(lastClaim);
        //uint8 dec = IERC20Metadata(address(glp)).decimals();
        resetCounter();
        //console.log("    SOL - dec", dec);
        //console.log("    SOL - timeDiff", timeDiff);
        //console.log("    SOL - 365 days", 365 days);
        //console.log("    SOL - apr", uint256(apr));

        uint256 usdValue = glp.balanceOf(msg.sender).mul(priceFeed.getGLPprice()).div(10**30);
        //console.log("    SOL - usdValue of current glp", usdValue.div(10**14));

        if(usdValue > 0){
            //console.log("    SOL - current glp", glp.balanceOf(msg.sender).div(10**14));
            //console.log("    SOL - current glp price", priceFeed.getGLPprice().div(10**26));
            
            usdValue = usdValue.mul(uint256(apr)).mul(timeDiff).div(10000).div(365 days);
            
            //console.log("    SOL - usdValue of reward", usdValue.div(10**14));

            //uint256 
            uint256 wethAmount = usdValue.mul(10**30).div(priceFeed.getPrice(address(weth)));
            //console.log("    SOL - wethAmount of reward", wethAmount);
            weth.mint(msg.sender, wethAmount);
        }
    }

    function claimEsGmx() external{

    }

    function stakeEsGmx(uint256 _amount) external{

    }
}