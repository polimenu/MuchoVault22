// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../interfaces/IMuchoBadgeManager.sol";

contract MuchoBadgeManagerMock is IMuchoBadgeManager{
    function activePlansForUser(address _user) external view returns (Plan[] memory){
        return new Plan[](0);
    }
}