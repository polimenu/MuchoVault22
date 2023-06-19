// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../../interfaces/GMX/IGLPRouter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../../interfaces/GMX/IGLPPriceFeed.sol";
import "../../../interfaces/GMX/IGLPVault.sol";
import "../../../interfaces/IMuchoToken.sol";
import "hardhat/console.sol";


contract GLPRouterMock is IGLPRouter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IMuchoToken glp;
    IERC20[3] primaryTokens;
    IGLPPriceFeed priceFeed;
    IGLPVault glpVault;

    constructor(
        IGLPVault _glpVault,
        IGLPPriceFeed _pFeed,
        IMuchoToken _glp,
        IERC20 _usdc,
        IERC20 _weth,
        IERC20 _wbtc
    ) {
      glpVault = _glpVault;
      priceFeed = _pFeed;
      glp = _glp;
      primaryTokens[0] = _usdc;
      primaryTokens[1] = _weth;
      primaryTokens[2] = _wbtc;
    }

    //Swap glp to a token and send it to sender
    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256) {
      IERC20 token = findToken(_tokenOut);

      //calc glp amount to burn
      uint256 burnFee = glpVault.getFeeBasisPoints(_tokenOut, 1, 1, 1, false);
      uint256 usdGlp = priceFeed.getGLPprice().mul(_glpAmount).div(10**30).mul(10000 - burnFee).div(10000);
      uint256 priceOriginalToken = priceFeed.getPrice(address(token)).div(10**30);
      uint256 tkAmount = usdGlp.mul(1 ether).div(priceOriginalToken);

      //burn glp
      glp.burn(msg.sender, _glpAmount);

      //transfer original token to sender
      glpVault.allowRouter(address(token), tkAmount);
      console.log("Transferring", address(this), address(token), tkAmount);
      token.safeTransferFrom(address(glpVault), msg.sender, tkAmount);
    }

    //Swap a token to glp and send it to sender
    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256) {
      IERC20 token = findToken(_token);

      //store original token in this contract
      //token.safeTransferFrom(msg.sender, address(glpVault), _amount);
      glpVault.receiveTokenFrom(msg.sender, address(token), _amount);
      console.log("Sent to vault token", address(token), _amount);

      //calc glp amount to mint
      uint256 mintFee = glpVault.getFeeBasisPoints(_token, 1, 1, 1, true);
      console.log("mintFee", mintFee);
      uint256 glpPrice = priceFeed.getGLPprice();
      console.log("glpPrice", glpPrice);
      uint256 usdOriginalToken = priceFeed.getPrice(address(token)).mul(_amount).div(10**30);
      console.log("usdOriginalToken", usdOriginalToken);
      uint256 tkAmount = usdOriginalToken.mul(1 ether).div(glpPrice).mul(10000 - mintFee).div(10000);
      console.log("tkAmount", tkAmount);

      //mint glp
      glp.mint(msg.sender, tkAmount);
    }


    function findToken(address _token) internal view returns(IERC20){
      for(uint8 i = 0; i < primaryTokens.length; i++){
        if(address(primaryTokens[i]) == _token)
          return primaryTokens[i];
      }

      revert("findToken: token not added to mock");
    }
}
