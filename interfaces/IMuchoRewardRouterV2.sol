// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/*
MuchoRewardRouterV2

Contrato que manejan los rewards
Guarda liquidez. A diferencia de la versión anterior, este es agnóstico a NFT's, etc. le viene todo masticado
Owner: MuchoHUB

Operaciones de depósito de rewards (público): 
    depositRewards
    withdraw

*/

interface IMuchoRewardRouterV2 {
    event RewardDeposited(address token, address user, uint256 amount);
    event Withdrawn(address token, uint256 amount);

    //Deposit the rewards and split among the users
    function depositRewards(address _token, uint256 _amount) external;

    //Withdraws all the rewards the user has
    function withdrawToken(address _token) external returns (uint256);

    //Withdraws all the rewards the user has
    function withdraw() external;
}
