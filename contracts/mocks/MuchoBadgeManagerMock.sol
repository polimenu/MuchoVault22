// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../../interfaces/IMuchoBadgeManager.sol";



contract MuchoBadgeManagerMock is IMuchoBadgeManager{

    mapping(address => Plan[]) userPlan;
    Plan[] plans;
    
    constructor(){
        plans.push(Plan({id:1, name:"Plan1", uri:"", subscribers:0, subscriptionPrice:Price({token:address(0), amount:0}), renewalPrice:Price({token:address(0), amount:0}), time:block.timestamp, exists:true, enabled:true}));
        plans.push(Plan({id:2, name:"Plan2", uri:"", subscribers:0, subscriptionPrice:Price({token:address(0), amount:0}), renewalPrice:Price({token:address(0), amount:0}), time:block.timestamp, exists:true, enabled:true}));
        plans.push(Plan({id:3, name:"Plan3", uri:"", subscribers:0, subscriptionPrice:Price({token:address(0), amount:0}), renewalPrice:Price({token:address(0), amount:0}), time:block.timestamp, exists:true, enabled:true}));
        plans.push(Plan({id:4, name:"Plan4", uri:"", subscribers:0, subscriptionPrice:Price({token:address(0), amount:0}), renewalPrice:Price({token:address(0), amount:0}), time:block.timestamp, exists:true, enabled:true}));
    }

    function addUserToPlan(address _user, uint256 _planId) external{
        userPlan[_user].push(plans[_planId - 1]);
    }

    function activePlansForUser(address _user) external view returns (Plan[] memory){
        return userPlan[_user];
    }
}