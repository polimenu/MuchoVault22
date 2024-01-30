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
import '../../interfaces/GMXv2/IMuchoProtocolGMXv2Logic.sol';

contract MuchoProtocolGMXv2Logic is IMuchoProtocolGMXv2Logic {
    //Gets the invest split
    function getTokensInvestment(
        GmPool[] calldata pools,
        TokenAmount[] calldata longUsdAmounts,
        uint256 shortUsdAmount,
        uint256 minNotInvested
    ) external pure returns (uint256[] memory longs, uint256[] memory shorts) {
        uint256 MIN_SHORT = 10000000;

        /*
        1.- Por cada pool, con el long que tenemos, calcular cuánto short necesitamos en total
        De paso validamos que existe el long en todos los pools
        */
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

        //2.- Si basta el short, palante (respetando el min not invested en cada pool)
        if (shortUsdAmount < totalShortUsdNeeded) {
            uint256 availableUsdShort = shortUsdAmount;

            /*3.- Si no basta el short, repartir el short en cada pool:
                mínimo entre short necesitado por el pool, y short total / num pools
                iterar hasta acabar el short o que quede el min not invested
        */
            for (uint16 i = 0; i < pools.length + 1; i++) {
                if (availableUsdShort < MIN_SHORT) {
                    break;
                }

                uint256 shortPortion = availableUsdShort / pools.length;

                for (uint256 iPool = 0; iPool < pools.length; iPool++) {
                    uint256 maxLongAddable = (i == 0) ? longs[iPool] : (longUsdAmounts[iPool].amountUsd - longs[iPool]);
                    uint256 maxShortAddable = (maxLongAddable / pools[iPool].longWeight) - maxLongAddable;

                    if (maxShortAddable > shortPortion) {
                        maxShortAddable = shortPortion;
                        maxLongAddable = (maxShortAddable / (10000 - pools[iPool].longWeight)) - maxShortAddable;
                    }

                    longs[iPool] += maxLongAddable;
                    shorts[iPool] += maxShortAddable;

                    availableUsdShort -= maxShortAddable;
                }
            }
        }
    }
}
