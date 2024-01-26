/*                               %@@@@@@@@@@@@@@@@@(                              
                        ,@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                        
                    /@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@.                   
                 &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(                
              ,@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@              
            *@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            
           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@          
         &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*        
        @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&       
       @@@@@@@@@@@@@   #@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@   &@@@@@@@@@@@      
      &@@@@@@@@@@@    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@.   @@@@@@@@@@,     
      @@@@@@@@@@&   .@@@@@@@@@@@@@@@@@&@@@@@@@@@&&@@@@@@@@@@@#   /@@@@@@@@@     
     &@@@@@@@@@@    @@@@@&                 %          @@@@@@@@,   #@@@@@@@@,    
     @@@@@@@@@@    @@@@@@@@%       &&        *@,       @@@@@@@@    @@@@@@@@%    
     @@@@@@@@@@    @@@@@@@@%      @@@@      /@@@.      @@@@@@@@    @@@@@@@@&    
     @@@@@@@@@@    &@@@@@@@%      @@@@      /@@@.      @@@@@@@@    @@@@@@@@/    
     .@@@@@@@@@@    @@@@@@@%      @@@@      /@@@.      @@@@@@@    &@@@@@@@@     
      @@@@@@@@@@@    @@@@&         @@        .@          @@@@.   @@@@@@@@@&     
       @@@@@@@@@@@.   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@    @@@@@@@@@@      
        @@@@@@@@@@@@.  @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@   @@@@@@@@@@@       
         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@        
          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#         
            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           
              @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             
                &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@/               
                   &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@(                  
                       @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#                      
                            /@@@@@@@@@@@@@@@@@@@@@@@*  */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;
import '../../lib/GmPool.sol';

contract MuchoProtocolGMXv2Logic {
    struct TokenAmount {
        address token;
        uint256 amountUsd;
    }

    //Gets the invest split
    function getTokensInvestment(
        GmPool[] calldata pools,
        TokenAmount[] calldata longUsdAmounts,
        uint256 shortUsdAmount,
        uint256 minNotInvested
    ) external pure returns (uint256[] memory longs, uint256[] memory shorts) {
        /*
        1.- Por cada pool, con el long que tenemos, calcular cuánto short necesitamos
        2.- Si basta el short, p'alante (respetando el min not invested en cada pool)
        3.- Si no basta el short, repartir el short en cada pool:
                mínimo entre short necesitado por el pool, y short total / num pools
                iterar hasta acabar el short o que quede el min not invested
        */

        //Validate tokens for all pools
        uint256 totalShortUsdNeeded = 0; //Take advantage of the same loop to calculate total short needed
        for (uint256 iPool = 0; iPool < pools.length; iPool++) {
            bool found = false;

            for (uint256 iLong = 0; iLong < longUsdAmounts.length; iLong++) {
                if (longUsdAmounts[iLong].token == pools[iPool].long) {
                    found = true;

                    longs[iPool] = (longUsdAmounts[iLong].amountUsd * (10000 - minNotInvested)) / 10000;
                    shorts[iPool] = (longs[iPool] / pools[iPool].longWeight) - longs[iPool];

                    totalShortUsdNeeded += shorts[iPool];

                    break;
                }
            }

            require(found, 'MuchoProtocolGMXv2Logic: tokens do not match with pools');
        }

        //2.- Si basta el short, p'alante (respetando el min not invested en cada pool)
        /*3.- Si no basta el short, repartir el short en cada pool:
                mínimo entre short necesitado por el pool, y short total / num pools
                iterar hasta acabar el short o que quede el min not invested
        */
        if (shortUsdAmount < totalShortUsdNeeded) {
            uint256 availableUsdShort = shortUsdAmount;

            //max 10 iterations (limit gas)
            for (uint16 i = 0; i < 10; i++) {
                for (uint256 iPool = 0; iPool < pools.length; iPool++) {}
            }
        }
    }
}
