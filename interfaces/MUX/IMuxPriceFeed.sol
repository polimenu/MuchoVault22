// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../interfaces/IPriceFeed.sol";

interface IMuxPriceFeed is IPriceFeed {

    function getMUXprice() external view returns (uint256);
}
