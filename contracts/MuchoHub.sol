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
//import "hardhat/console.sol";

contract MuchoHub is IMuchoHub, MuchoRoles, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    EnumerableSet.AddressSet protocolList;
    mapping(address => InvestmentPartition) tokenDefaultInvestment;
    uint256 public lastFullRefresh;

    modifier checkPartitionList(InvestmentPart[] memory _partitionList) {
        uint256 total = 0;
        for (uint256 i = 0; i < _partitionList.length; i = i.add(1)) {
            require(
                protocolList.contains(_partitionList[i].protocol),
                "MuchoHub: Partition list contains not active protocol"
            );
            total = total.add(_partitionList[i].percentage);
        }
        require(
            total == 10000,
            "MuchoHub: Partition list total is not 100% of investment"
        );
        _;
    }

    modifier activeProtocol(address _protocol) {
        require(
            protocolList.contains(_protocol),
            "MuchoHub: Protocol not in the list"
        );
        _;
    }

    function addProtocol(address _contract) external onlyAdmin {
        protocolList.add(_contract);
    }

    function removeProtocol(address _contract) external onlyAdmin {
        protocolList.remove(_contract);
    }

    function setDefaultInvestment(
        address _token,
        InvestmentPart[] memory _partitionList
    ) external onlyTraderOrAdmin checkPartitionList(_partitionList) {
        tokenDefaultInvestment[_token].defined = true;
        for (uint256 i = 0; i < _partitionList.length; i = i.add(1)) {
            tokenDefaultInvestment[_token].parts.push(
                InvestmentPart({
                    percentage: _partitionList[i].percentage,
                    protocol: _partitionList[i].protocol
                })
            );
        }
    }

    function moveInvestment(
        address _token,
        uint256 _amount,
        address _protocolSource,
        address _protocolDestination
    )
        external
        onlyTraderOrAdmin
        nonReentrant
        activeProtocol(_protocolDestination)
    {
        IMuchoProtocol protSource = IMuchoProtocol(_protocolSource);
        /*console.log("    SOL MuchoHub - Moving", _amount);
        console.log("    SOL MuchoHub - Staked source", protSource.getTotalStaked(_token));*/
        require(protSource.getTotalStaked(_token) >= _amount, "MuchoHub: Cannot move more than staked");
        protSource.withdrawAndSend(_token, _amount, _protocolDestination);
    }

    function depositFrom(
        address _investor,
        address _token,
        uint256 _amount
    ) external onlyOwner nonReentrant {
        IERC20 tk = IERC20(_token);
        require(
            tk.allowance(_investor, address(this)) >= _amount,
            "MuchoHub: not enough allowance"
        );
        require(
            tokenDefaultInvestment[_token].defined,
            "MuchoHub: no protocol defined for the token"
        );

        for (
            uint256 i = 0;
            i < tokenDefaultInvestment[_token].parts.length;
            i = i.add(1)
        ) {
            InvestmentPart memory part = tokenDefaultInvestment[_token].parts[
                i
            ];
            uint256 amountProtocol = _amount.mul(part.percentage).div(10000);

            //Send the amount and update investment in the protocol
            IMuchoProtocol(part.protocol).cycleRewards();
            tk.safeTransferFrom(_investor, part.protocol, amountProtocol);
            IMuchoProtocol(part.protocol).notifyDeposit(_token, amountProtocol);
            IMuchoProtocol(part.protocol).refreshInvestment();
        }
    }

    function withdrawFrom(
        address _investor,
        address _token,
        uint256 _amount
    ) external onlyOwner nonReentrant {
        require(_amount < getTotalStaked(_token), "Cannot withdraw more than total staked");
        uint256 amountPending = _amount;

        /*console.log("    SOL MuchoHub - WITHDRAW");
        console.log("    SOL MuchoHub - Start with not invested, pending: ", amountPending);*/

        //First, not invested volumes
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            amountPending = amountPending.sub(
                IMuchoProtocol(protocolList.at(i)).notInvestedTrySend(_token, amountPending, _investor)
            );

            //console.log("    SOL MuchoHub - protocol done, pending: ", amountPending);

            if (amountPending == 0)
                //Already filled amount
                return;
        }

        //console.log("    SOL MuchoHub - Continue with invested, pending: ", amountPending);

        //Secondly, invested volumes proportional to usd volume
        (uint256 totalInvested, uint256[] memory amountList) = getTotalInvestedAndList(_token);
        uint256 amountTotalWithdrawFromInvested = amountPending;
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            //console.log("    SOL MuchoHub - iteration invested ", amountList[i], totalInvested);
            uint256 amountProtocol = amountTotalWithdrawFromInvested.mul(amountList[i]).div(totalInvested);
            uint256 amountToWithdraw = (amountProtocol > amountPending) ? amountPending : amountProtocol;
            //console.log("    SOL MuchoHub - amount to withdraw ", amountToWithdraw);

            amountPending = amountPending.sub(amountToWithdraw);

            IMuchoProtocol(protocolList.at(i)).withdrawAndSend(_token, amountToWithdraw, _investor);

            //console.log("    SOL MuchoHub - protocol done, pending: ", amountPending);

            if (amountPending == 0)
                //Already filled amount
                return;
        }

        //IF there is a rest (from dividing rounding), fill it easy
        (totalInvested, amountList) = getTotalInvestedAndList(_token);
        if(amountPending < totalInvested){
        //console.log("    SOL MuchoHub - Continue with invested RESTO, pending: ", amountPending);
            for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
                //console.log("    SOL MuchoHub - iteration invested RESTO ", amountList[i], totalInvested);
                
                uint256 amountToWithdraw = (amountList[i] > amountPending) ? amountPending : amountList[i];
                //console.log("    SOL MuchoHub - amount to withdraw ", amountToWithdraw);
                amountPending = amountPending.sub(amountToWithdraw);
                IMuchoProtocol(protocolList.at(i)).withdrawAndSend(_token, amountToWithdraw, _investor);
                //console.log("    SOL MuchoHub - protocol done, pending: ", amountPending);

                if (amountPending == 0)
                    //Already filled amount
                    return;
            }
        }

        revert("Could not fill needed amount");
    }

    function refreshInvestment(
        address _protocol
    ) public onlyTraderOrAdmin activeProtocol(_protocol) {
        IMuchoProtocol(_protocol).cycleRewards();
        IMuchoProtocol(_protocol).refreshInvestment();
    }

    function refreshAllInvestments() external onlyTraderOrAdmin {
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            refreshInvestment(protocolList.at(i));
        }
        lastFullRefresh = block.timestamp;
    }

    function protocols() external view returns (address[] memory) {
        address[] memory list = new address[](protocolList.length());
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            list[i] = protocolList.at(i);
        }

        return list;
    }

    function getTotalNotInvested(
        address _token
    ) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            total = total.add(
                IMuchoProtocol(protocolList.at(i)).getTotalNotInvested(_token)
            );
        }
        return total;
    }

    function getTotalStaked(address _token) public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            total = total.add(
                IMuchoProtocol(protocolList.at(i)).getTotalStaked(_token)
            );
        }
        return total;
    }

    function getTokenDefaults(
        address _token
    ) external view returns (InvestmentPart[] memory) {
        require(
            tokenDefaultInvestment[_token].defined,
            "MuchoHub: Default investment not defined for token"
        );
        return tokenDefaultInvestment[_token].parts;
    }

    function getTotalInvestedAndList(
        address _token
    ) internal view returns (uint256, uint256[] memory) {
        uint256 total = 0;
        uint256[] memory amounts = new uint256[](protocolList.length());
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            IMuchoProtocol prot = IMuchoProtocol(protocolList.at(i));
            amounts[i] = prot.getTotalInvested(_token);
            total = total.add(amounts[i]);
        }
        return (total, amounts);
    }

    function getTotalUSD() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            total = total.add(IMuchoProtocol(protocolList.at(i)).getTotalUSD());
        }
        return total;
    }

    function getCurrentInvestment(
        address _token
    ) external view returns (InvestmentAmountPartition memory) {
        InvestmentAmountPart[] memory parts = new InvestmentAmountPart[](
            protocolList.length()
        );
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            parts[i].protocol = protocolList.at(i);
            parts[i].amount = IMuchoProtocol(protocolList.at(i)).getTotalStaked(
                _token
            );
        }
        InvestmentAmountPartition memory out = InvestmentAmountPartition({
            parts: parts
        });
        return out;
    }
}
