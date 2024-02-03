// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGmxDataStore {
    function getUint(bytes32 key) external view returns (uint256);
}
