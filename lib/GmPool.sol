// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

struct GmPool {
    address gmAddress;
    address long;
    uint256 longWeight;
    bool enabled;
    uint256 gmApr;
    bytes32 positiveSwapFee;
    bytes32 negativeSwapFee;
}
