// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;


interface IvMlp {

    function claimable(address _account) external view returns (uint256);
}
