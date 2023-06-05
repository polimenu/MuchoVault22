// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
//import "hardhat/console.sol";

struct AprInfo{
        uint256 lastAprUpdate;     //Last update the APR was updated - we intend to do this daily
        uint256 lastTotalStaked;    //we store this next 2, to calculate next period apr
        uint256 lastStakedFromDeposits;
        int256[30] apr;            //We store last 30 days aprs
}

library AprLib{

    using SafeMath for uint256;

    function updateApr(AprInfo storage a, uint256 totalStaked, uint256 stakedFromDeposits) internal{
        //Move all the apr periods backwards
        for(uint8 i = 29; i >= 1; i--){
            a.apr[i] = a.apr[i-1];
        }

        //Calc last period apr and store it
        if(a.lastTotalStaked != 0 && a.lastStakedFromDeposits != 0){
            /*console.log("   SOL - Updating APR");
            console.log("   SOL - totalStaked", totalStaked);
            console.log("   SOL - stakedFromDeposits", stakedFromDeposits);
            console.log("   SOL - lastTotalStaked", a.lastTotalStaked);
            console.log("   SOL - lastStakedFromDeposits", a.lastStakedFromDeposits);*/
            int256 profit = int256(totalStaked) - int256(a.lastTotalStaked) - int256(stakedFromDeposits) + int256(a.lastStakedFromDeposits);
            /*if(profit<0){
                console.log("Negative profit");
                console.log(uint256(-profit));
            }
            else{
                console.log("   SOL - Positive profit", uint256(profit));
            }*/
            int256 avgDeposit = int256(a.lastTotalStaked.mul(2).add(stakedFromDeposits).sub(a.lastStakedFromDeposits).div(2));
            /*if(avgDeposit<0){
                console.log("Negative avgDeposit");
                console.log(uint256(-avgDeposit));
            }
            else{
                console.log("   SOL - Positive avgDeposit", uint256(avgDeposit));
            }*/
            /*console.log("   SOL - timediff", uint256(block.timestamp.sub(a.lastAprUpdate)));
            console.log("   SOL - 1 year", uint256(365 days));*/

            a.apr[0] = profit * int256(10000) * int256(365 days) / (int256(block.timestamp.sub(a.lastAprUpdate)) * avgDeposit);
            /*if(a.apr[0] >= 0)
                console.log("   SOL - APR  (+)", uint256(a.apr[0]));
            else
                console.log("   SOL - APR  (-)", uint256(-a.apr[0]));*/

        }
        else{
            //console.log("   SOL - APR  ZERO (zero staked)");
            a.apr[0] = 0;
        }

        a.lastAprUpdate = block.timestamp;
        a.lastStakedFromDeposits = stakedFromDeposits;
        a.lastTotalStaked = totalStaked;
    }
}