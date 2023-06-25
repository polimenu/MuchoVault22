// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../interfaces/IPriceFeed.sol";

contract PriceFeedMock is IPriceFeed{
    mapping(address => uint256) prices;

    constructor(address _usdc, address _weth, address _wbtc){
        prices[_usdc] = 1 * 10**30;
        prices[_weth] = 1600 * 10**30;
        prices[_wbtc] = 24000 * 10**30;
    }

    function addToken(address _token, uint256 _price) external{
        prices[_token] = _price;
    }

    function getPrice(address _token) external virtual view returns(uint256){
        return prices[_token];
    }
}