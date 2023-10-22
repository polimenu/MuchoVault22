// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IMuxOrderBook{
    function getOrderCount() external view returns (uint256 ) ;
    function getOrders( uint256 begin, uint256 end ) external view returns (bytes32[3][] memory orderArray, uint256 totalCount) ;
    function placeLiquidityOrder( uint8 assetId,uint96 rawAmount,bool isAdding ) external payable  ;
}