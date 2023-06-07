// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../lib/RewardSplit.sol";

/*
MuchoProtocol(s)

Contratos que manejan la inversión en un protocolo determinado
Guardan liquidez. Un upgrade podría ser posible, pero requeriría que el controller mueva la liquidez de un MuchoInvestor1 a un MuchoInvestor2
Liquidez no invertida. MuchoInvestor0 no invierte en ningún protocolo, simplemente guarda la liquidez
Owner: MuchoHUB (contrato)

Operaciones de trading (owner=MuchoHUB o trader): 
    refreshInvestment: rebalancea y actualiza la inversión
    cycleRewards
Operaciones de trading (owner=MuchoHUB): 
    withdrawAndSend: desinvierte en un token y lo envía a una dirección
Operaciones de configuración (protocolOwner): 
    definir porcentajes de compound, owner fee y NFT fee
    definir vault sobre el que se hace el compound de los rewards (por defecto, él mismo)
Operaciones de upgrade (protocolOwner): 
    cambiar direcciones de los contratos a los que se conecta

Vistas (públicas): getApr
*/

interface IMuchoProtocol{
    function protocolName() external returns(string memory);
    function protocolDescription() external returns(string memory);

    function refreshInvestment() external;
    function cycleRewards() external;

    function withdrawAndSend(address _token, uint256 _amount, address _target) external;
    function notInvestedTrySend(address _token, uint256 _amount, address _target) external returns(uint256);
    function notifyDeposit(address _token, uint256 _amount) external;

    function setRewardPercentages(RewardSplit memory _split) external;
    function setCompoundProtocol(IMuchoProtocol _target) external;
    function setMuchoRewardRouter(address _contract) external;

    function getLastPeriodsApr(address _token) external view returns(int256[30] memory);
    function getTotalNotInvested(address _token) external view returns(uint256);
    function getTotalStaked(address _token) external view returns(uint256);
    function getTotalUSD() external view returns(uint256);
}