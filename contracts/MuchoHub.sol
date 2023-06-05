// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IMuchoHub.sol";
import "../interfaces/IMuchoProtocol.sol";
import "./MuchoRoles.sol";

contract MuchoHub is IMuchoHub, MuchoRoles, ReentrancyGuard{
    using EnumerableSet for EnumerableSet.AddressSet;

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    EnumerableSet.AddressSet protocolList;
    mapping(address => InvestmentPartition) tokenDefaultInvestment;
    IMuchoProtocol defaultProtocol;
    uint256 public lastFullRefresh;


    modifier checkPartitionList(InvestmentPart[] memory _partitionList){
        uint256 total = 0;
        for(uint256 i = 0; i < _partitionList.length; i = i.add(1)){
            require(protocolList.contains(_partitionList[i].protocol), "MuchoHub: Partition list contains not active protocol");
            total = total.add(_partitionList[i].percentage);
        }
        require(total == 10000, "MuchoHub: Partition list total is not 100% of investment");
        _;
    }

    modifier activeProtocol(address _protocol){
        require(protocolList.contains(_protocol), "MuchoHub: Protocol not in the list");
        _;
    }

    function addProtocol(address _contract) onlyAdmin external{
        protocolList.add(_contract);
    }
    function removeProtocol(address _contract) onlyAdmin external{
        protocolList.remove(_contract);
    }
    function setDefaultProtocol(IMuchoProtocol _newProtocol) onlyAdmin external{
        defaultProtocol = _newProtocol;
    }

    function setDefaultInvestment(address _token, InvestmentPart[] memory _partitionList) 
                                                            onlyTraderOrAdmin checkPartitionList(_partitionList) external{
        tokenDefaultInvestment[_token].defined = true;
        for(uint256 i = 0; i < _partitionList.length; i = i.add(1)){
            tokenDefaultInvestment[_token].parts[i] = InvestmentPart({percentage: _partitionList[i].percentage, protocol: _partitionList[i].protocol});
        }
    }

    function moveInvestment(address _token, uint256 _amount, address _protocolSource, address _protocolDestination) 
                                onlyTraderOrAdmin nonReentrant
                                activeProtocol(_protocolDestination) external{
        IMuchoProtocol protSource = IMuchoProtocol(_protocolSource);
        protSource.withdrawAndSend(_token, _amount, _protocolDestination);
    }

    function depositFrom(address _investor, address _token, uint256 _amount) onlyOwner nonReentrant external{
        IERC20 tk = IERC20(_token);
        require(tk.allowance(_investor, address(this)) >= _amount, "MuchoHub: not enough allowance");
        require(tokenDefaultInvestment[_token].defined, "MuchoHub: no protocol defined for the token");
        
        for(uint256 i = 0; i < tokenDefaultInvestment[_token].parts.length; i = i.add(1)){
            InvestmentPart memory part = tokenDefaultInvestment[_token].parts[i];
            uint256 amountProtocol = _amount.mul(part.percentage).div(10000);

            //Send the amount and update investment in the protocol
            tk.safeTransferFrom(_investor, part.protocol, amountProtocol);
            IMuchoProtocol(part.protocol).notifyDeposit(_token, amountProtocol);
            IMuchoProtocol(part.protocol).refreshInvestment();
        }
    }

    function withdrawFrom(address _investor, address _token, uint256 _amount) onlyOwner nonReentrant external{
        uint256 amountPending = _amount;

        //First, not invested volumes
        for(uint256 i = 0; i < protocolList.length(); i = i.add(1)){
            amountPending = amountPending.sub(IMuchoProtocol(protocolList.at(i)).notInvestedTrySend(_token, amountPending, _investor));

            if(amountPending == 0) //Already filled amount
                return;
        }

        //Secondly, invested volumes proportional to usd volume
        (uint256 totalUSD, uint256[] memory usdList) = getTotalUSDAndList();
        for(uint256 i = 0; i < protocolList.length(); i = i.add(1)){
            uint256 amountToWithdraw = amountPending.mul(usdList[i]).div(totalUSD);
            amountPending = amountPending.sub(IMuchoProtocol(protocolList.at(i)).notInvestedTrySend(_token, amountToWithdraw, _investor));

            if(amountPending == 0) //Already filled amount
                return;
        }

        revert("Could not fill needed amount");
    }


    function refreshInvestment(address _protocol) onlyTraderOrAdmin activeProtocol(_protocol) public{
        IMuchoProtocol(_protocol).refreshInvestment();
    }
    function refreshAllInvestments() onlyTraderOrAdmin external{
        for(uint256 i = 0; i < protocolList.length(); i = i.add(1)){
            refreshInvestment(protocolList.at(i));
        }
        lastFullRefresh = block.timestamp;
    }

    function protocols() external view returns(address[] memory){
        address[] memory list = new address[](protocolList.length());
        for(uint256 i = 0; i < protocolList.length(); i = i.add(1)){
            list[i] = protocolList.at(i);
        }

        return list;
    }
    function getTotalNotInvested(address _token) external view returns(uint256){
        uint256 total = 0;
        for(uint256 i = 0; i < protocolList.length(); i = i.add(1)){
            total = total.add(IMuchoProtocol(protocolList.at(i)).getTotalNotInvested(_token));
        }
        return total;
    }
    function getTotalStaked(address _token) external view returns(uint256){
        uint256 total = 0;
        for(uint256 i = 0; i < protocolList.length(); i = i.add(1)){
            total = total.add(IMuchoProtocol(protocolList.at(i)).getTotalStaked(_token));
        }
        return total;
    }
    function getTokenDefaults(address _token) external view returns(InvestmentPartition memory){
        return tokenDefaultInvestment[_token];
    }
    function getTotalUSDAndList() public view returns(uint256, uint256[] memory){
        uint256 total = 0;
        uint256[] memory usd = new uint256[](protocolList.length());
        for(uint256 i = 0; i < protocolList.length(); i = i.add(1)){
            usd[i] = IMuchoProtocol(protocolList.at(i)).getTotalUSD();
            total = total.add(usd[i]);
        }
        return (total, usd);
    }

}