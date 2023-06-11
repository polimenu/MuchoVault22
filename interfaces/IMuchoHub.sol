// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "../lib/InvestmentPartition.sol";

/*
CONTRATO MuchoHub:

HUB de conexión con las inversiones en distintos protocolos
No guarda liquidez. Potencialmente upgradeable
Guarda una una lista de contratos MuchoInvestment, cada uno de los cuales mantiene la inversión en un protocolo diferente
En caso de upgrade deberíamos crear estructura gemela en el nuevo contrato
Es el owner de los contratos MuchoInvestment, lo que le permite mover su liquidez
En caso de upgrade tendría que transferir ese ownership
Owner: contrato MuchoVault

Operaciones de inversión (owner=MuchoVault): deposit, withdraw
Operaciones de configuración (protocolOwner): añadir, modificar o desactivar contratos MuchoInvestment (protocolos)
Operaciones de trading (trader o protocolOwner): 
        moveInvestment: mover liquidez de un MuchoInvestment a otro
        setDefaultInvestment: determinar los MuchoInvestment por defecto y su porcentaje, para cada token al agregar nueva liquidez un inversor (si no se especifica, irá al 0)
        refreshAllInvestments: llamará a updateInvestment de cada MuchoInvestment (ver siguiente slide)

Operaciones de upgrade (protocolOwner): cambiar direcciones de los contratos a los que se conecta

Vistas (públicas): getApr
*/

interface IMuchoHub{
    function depositFrom(address _investor, address _token, uint256 _amount) external;
    function withdrawFrom(address _investor, address _token, uint256 _amount) external;

    function addProtocol(address _contract) external;
    function removeProtocol(address _contract) external;

    function moveInvestment(address _token, uint256 _amount, address _protocolSource, address _protocolDestination) external;
    function setDefaultInvestment(address _token, InvestmentPart[] calldata _partitionList) external;

    function refreshInvestment(address _protocol) external;
    function refreshAllInvestments() external;

    function getTotalNotInvested(address _token) external view returns(uint256);
    function getTotalStaked(address _token) external view returns(uint256);
    function getTotalUSD() external view returns(uint256);
    function getProtocols() external view returns(address[] memory);
    function getDefaultInvestment(address _token) external view returns(InvestmentPartition memory);
    function getCurrentInvestment(address _token) external view returns(InvestmentAmountPartition memory);
}