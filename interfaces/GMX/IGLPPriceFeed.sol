// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../interfaces/IPriceFeed.sol";

interface IGLPPriceFeed is IPriceFeed {

    function getGLPprice() external view returns (uint256);
}
