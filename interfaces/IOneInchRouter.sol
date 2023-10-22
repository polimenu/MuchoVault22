// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IOneInchRouter{
    function uniswapV3Swap(uint256 amount, uint256 minReturn, uint256[] calldata pools) external;
}
