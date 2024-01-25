// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../interfaces/MUX/IMuxPriceFeed.sol";
import "../MuchoRoles.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MuxPriceFeed is IMuxPriceFeed, MuchoRoles {
     using SafeMath for uint256;
    
    //We rely on GLP pool (GMX) to get prices
    GLPpool pool = GLPpool(0x489ee077994B6658eAfA855C308275EAd8097C4A);

    //MUX price is pushed off-chain
    uint256 mlpPrice;
    function setMLPPrice(uint256 _price) external onlyTraderOrAdmin{
        mlpPrice = _price;
    }

    function updatePool(GLPpool _pool) external onlyAdmin{
        pool = _pool;
    }

    function getMLPprice() external view returns (uint256){
        return mlpPrice;
    }


    function getPrice(address _token) public view returns (uint256){
        return pool.getMinPrice(_token);
    }
}

interface GLPpool {
    function getMinPrice(address _token) external view returns (uint256);
    function getMaxPrice(address _token) external view returns (uint256);
}