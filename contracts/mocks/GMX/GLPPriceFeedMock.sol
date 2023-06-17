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
    IERC20 weth;
    IERC20 wbtc;

    constructor(address _usdc, address _weth, address _wbtc,
        IGLPVault _glpVault, IERC20 _glp) PriceFeedMock(_usdc, _weth, _wbtc){
        
        glpVault = _glpVault;
        glp = _glp;
        usdc = IERC20(_usdc);
        weth = IERC20(_weth);
        wbtc = IERC20(_wbtc);
    }

    function getGLPprice() external view returns (uint256){

        return glpVault.usdgAmounts(address(usdc))
                    .add(glpVault.usdgAmounts(address(weth)))
                    .add(glpVault.usdgAmounts(address(wbtc)))
                    .mul(1 ether)
                    .div(glp.totalSupply());
    }

}
