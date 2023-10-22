// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;


interface IMlpRewardRouter{
    function claimAll(  ) external   ;
    function depositToMlpVester( uint256 amount ) external   ;
    function stakeMlp( uint256 _amount ) external  returns (uint256 ) ;
}