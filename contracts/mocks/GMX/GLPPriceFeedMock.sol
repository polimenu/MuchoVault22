// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../../interfaces/GMX/IGLPPriceFeed.sol";
import "../../../interfaces/GMX/IGLPVault.sol";
import "../PriceFeedMock.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GLPPriceFeedMock is IGLPPriceFeed, PriceFeedMock {

    using SafeMath for uint256;

    IERC20 glp;
    IGLPVault glpVault;
    IERC20 usdc;
    IERC20 usdt;
    IERC20 dai;
    IERC20 weth;
    IERC20 wbtc;

    constructor(address _usdc, address _usdt, address _dai, address _weth, address _wbtc,
        IGLPVault _glpVault, IERC20 _glp) PriceFeedMock(_usdc, _weth, _wbtc){
        
        glpVault = _glpVault;
        glp = _glp;
        usdc = IERC20(_usdc);
        usdt = IERC20(_usdt);
        dai = IERC20(_dai);
        weth = IERC20(_weth);
        wbtc = IERC20(_wbtc);
    }

    function getGLPprice() external view returns (uint256){
        require(glp.totalSupply() > 0, "GLPPriceFeedMock.getGLPPrice: No GLP supply");
        //console.log("********GET GLP PRICE*************");
        //console.log("USDG amounts", glpVault.usdgAmounts(address(usdc))
        //            .add(glpVault.usdgAmounts(address(weth)))
        //            .add(glpVault.usdgAmounts(address(wbtc))));
        //console.log("GLP supply", glp.totalSupply());
        return glpVault.usdgAmounts(address(usdc))
                    .add(glpVault.usdgAmounts(address(weth)))
                    .add(glpVault.usdgAmounts(address(usdt)))
                    .add(glpVault.usdgAmounts(address(dai)))
                    .add(glpVault.usdgAmounts(address(wbtc)))
                    .mul(10**12)
                    .div(glp.totalSupply());
    }

}
