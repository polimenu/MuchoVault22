// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGmxV2PriceFeed {
    function getPrice(address _token) external view returns (uint256);

    function hasOracle(address _token) external view returns (bool);
}
