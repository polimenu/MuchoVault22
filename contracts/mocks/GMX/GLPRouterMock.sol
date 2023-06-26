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
      console.log("    SOL***unstakeAndRedeemGlp***", _tokenOut, _glpAmount);
      IERC20 token = findToken(_tokenOut);

      //calc glp amount to burn
      uint8 decimalsToken = IERC20Metadata(_tokenOut).decimals();
      uint256 burnFee = glpVault.getFeeBasisPoints(_tokenOut, 1, 1, 1, false);
      console.log("    SOL - burnFee", burnFee);
      uint256 usdGlp = priceFeed.getGLPprice().mul(_glpAmount).div(10**30).mul(10000 - burnFee).div(10000);
      uint256 tkAmount = usdGlp.mul(10**(30+decimalsToken-18)).div(priceFeed.getPrice(address(token)));
      console.log("    SOL - usdGlp, tkAmount", usdGlp, tkAmount);

      //burn glp & mint, to simulate unstake and remove liquidity
      IMuchoToken(address(glp)).burn(msg.sender, _glpAmount);
      IMuchoToken(address(glp)).mint(address(glpVault), _glpAmount);

      //transfer original token to sender
      glpVault.allowRouter(address(token), tkAmount);
      console.log("    SOL - Transferring", address(this), address(token), tkAmount);
      token.safeTransferFrom(address(glpVault), msg.sender, tkAmount);
    }

    //Swap a token to glp and send it to sender
    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256) {
      //console.log("    SOL ***mintAndStakeGlp***");
      IERC20 token = findToken(_token);

      //store original token in this contract
      //token.safeTransferFrom(msg.sender, address(glpVault), _amount);
      glpVault.receiveTokenFrom(msg.sender, address(token), _amount);
      //console.log("    SOL - Sent to vault token", address(token), _amount);

      //calc glp amount to mint
      uint256 mintFee = glpVault.getFeeBasisPoints(_token, 1, 1, 1, true);
      //console.log("    SOL - mintFee", mintFee);
      uint256 glpPrice = priceFeed.getGLPprice();
      //console.log("    SOL - glpPrice", glpPrice.div(10**28));
      uint256 usdOriginalToken = priceFeed.getPrice(address(token)).mul(_amount).div(10**(30-18+IERC20Metadata(_token).decimals()));
      //console.log("       SOL - usdOriginalToken", usdOriginalToken.div(10**16));
      uint256 tkAmount = usdOriginalToken.mul(10**30).div(glpPrice).mul(10000 - mintFee).div(10000);
      //console.log("       SOL - tkAmount", tkAmount.div(10**16));

      //console.log("    SOL - minting glp address", address(glp));

      //send glp
      glpVault.sendGlpTo(msg.sender, tkAmount);
      return tkAmount;

      //console.log("    SOL ***END mintAndStakeGlp***");
    }


    function findToken(address _token) internal view returns(IERC20){
      for(uint8 i = 0; i < primaryTokens.length; i++){
        if(address(primaryTokens[i]) == _token)
          return primaryTokens[i];
      }

      revert("findToken: token not added to mock");
    }
}
