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

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '../interfaces/IMuchoHub.sol';
import '../interfaces/IMuchoProtocol.sol';
import './MuchoRoles.sol';

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
            require(protocolList.contains(_partitionList[i].protocol), 'MuchoHub: Partition list contains not active protocol');
            total = total.add(_partitionList[i].percentage);
        }
        require(total == 10000, 'MuchoHub: Partition list total is not 100% of investment');
        _;
    }

    modifier activeProtocol(address _protocol) {
        require(protocolList.contains(_protocol), 'MuchoHub: Protocol not in the list');
        _;
    }

    function addProtocol(address _contract) external onlyAdmin {
        protocolList.add(_contract);
        emit ProtocolAdded(_contract);
    }

    function removeProtocol(address _contract) external onlyAdmin {
        protocolList.remove(_contract);
        emit ProtocolRemoved(_contract);
    }

    function setDefaultInvestment(
        address _token,
        InvestmentPart[] memory _partitionList
    ) external onlyTraderOrAdmin checkPartitionList(_partitionList) {
        tokenDefaultInvestment[_token].defined = true;
        tokenDefaultInvestment[_token].parts = new InvestmentPart[](_partitionList.length);
        for (uint256 i = 0; i < _partitionList.length; i = i.add(1)) {
            tokenDefaultInvestment[_token].parts[i] = InvestmentPart({
                percentage: _partitionList[i].percentage,
                protocol: _partitionList[i].protocol
            });
        }
        emit DefaultInvestmentChanged(_token, _partitionList);
    }

    function moveInvestment(
        address _token,
        uint256 _amount,
        address _protocolSource,
        address _protocolDestination
    ) external onlyTraderOrAdmin nonReentrant activeProtocol(_protocolDestination) {
        IMuchoProtocol protSource = IMuchoProtocol(_protocolSource);
        /*console.log("    SOL MuchoHub - Moving", _amount);
        console.log("    SOL MuchoHub - Staked source", protSource.getTotalStaked(_token));*/
        require(protSource.getTokenStaked(_token) >= _amount, 'MuchoHub: Cannot move more than staked');
        uint256 pending = _amount.sub(protSource.notInvestedTrySend(_token, _amount, address(this)));
        if (pending > 0) protSource.withdrawAndSend(_token, pending, address(this));

        IERC20(_token).safeIncreaseAllowance(_protocolDestination, _amount);
        IMuchoProtocol(_protocolDestination).deposit(_token, _amount);
        emit InvestmentMoved(_token, _amount, _protocolSource, _protocolDestination);
    }

    function depositFrom(
        address _investor,
        address _token,
        uint256 _amount,
        uint256 _amountOwnerFee,
        address _feeDestination
    ) external onlyOwner nonReentrant {
        IERC20 tk = IERC20(_token);
        require(tk.allowance(_investor, address(this)) >= _amount.add(_amountOwnerFee), 'MuchoHub: not enough allowance');
        require(tokenDefaultInvestment[_token].defined, 'MuchoHub: no protocol defined for the token');

        //Get in the hub the total amount to invest that will be distributed
        //console.log("   SOL - depositFrom amount", _amount);
        //console.log("   SOL - depositFrom investor balance before", tk.balanceOf(_investor));
        tk.safeTransferFrom(_investor, address(this), _amount);
        //console.log("   SOL - depositFrom investor balance after", tk.balanceOf(_investor));

        for (uint256 i = 0; i < tokenDefaultInvestment[_token].parts.length; i = i.add(1)) {
            InvestmentPart memory part = tokenDefaultInvestment[_token].parts[i];
            uint256 amountProtocol = _amount.mul(part.percentage).div(10000);
            IMuchoProtocol p = IMuchoProtocol(part.protocol);
            tk.approve(part.protocol, amountProtocol);
            p.deposit(_token, amountProtocol);
            IMuchoProtocol(part.protocol).refreshInvestment();
        }

        if (_amountOwnerFee > 0) tk.safeTransferFrom(_investor, _feeDestination, _amountOwnerFee);

        if (tk.balanceOf(address(this)) > 0) tk.safeTransfer(_feeDestination, tk.balanceOf(address(this)));

        emit Deposited(_investor, _token, _amount, getTotalStaked(_token));

        //console.log("   SOL - depositFrom investor balance end", tk.balanceOf(_investor));
    }

    function withdrawFrom(
        address _investor,
        address _token,
        uint256 _amount,
        uint256 _amountOwnerFee,
        address _feeDestination
    ) external onlyOwner nonReentrant {
        require(_amount < getTotalStaked(_token), 'Cannot withdraw more than total staked');
        uint256 amountPending = _amount;
        uint256 feePending = _amountOwnerFee;

        /*console.log("    SOL MuchoHub - WITHDRAW");
        console.log("    SOL MuchoHub - Start with not invested, pending: ", amountPending);*/

        //First, not invested volumes
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            if (feePending > 0) {
                feePending = feePending.sub(IMuchoProtocol(protocolList.at(i)).notInvestedTrySend(_token, feePending, _feeDestination));
            }
            amountPending = amountPending.sub(IMuchoProtocol(protocolList.at(i)).notInvestedTrySend(_token, amountPending, _investor));

            //console.log("    SOL MuchoHub - protocol done, pending: ", amountPending);

            //Already filled amount
            if (amountPending == 0) {
                emit Withdrawn(_investor, _token, _amount, getTotalStaked(_token));
                return;
            }
        }

        //console.log("    SOL MuchoHub - Continue with invested, pending: ", amountPending);

        //Secondly, invested volumes proportional to usd volume
        (amountPending, feePending) = withdrawAmount(_token, amountPending, feePending, _investor, _feeDestination);

        //Already filled amount
        if (amountPending == 0) {
            emit Withdrawn(_investor, _token, _amount, getTotalStaked(_token));
            return;
        }

        //IF there is a rest (from dividing rounding), fill it easy
        (uint256 totalInvested, uint256[] memory amountList) = getTotalInvestedAndList(_token);
        if (amountPending < totalInvested) {
            //console.log("    SOL MuchoHub - Continue with invested RESTO, pending: ", amountPending);
            for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
                //console.log("    SOL MuchoHub - iteration invested RESTO ", amountList[i], totalInvested);

                uint256 amountToWithdraw = (amountList[i] > amountPending) ? amountPending : amountList[i];
                //console.log("    SOL MuchoHub - amount to withdraw ", amountToWithdraw);
                amountPending = amountPending.sub(amountToWithdraw);
                IMuchoProtocol(protocolList.at(i)).withdrawAndSend(_token, amountToWithdraw, _investor);
                //console.log("    SOL MuchoHub - protocol done, pending: ", amountPending);

                //Already filled amount
                if (amountPending == 0) {
                    emit Withdrawn(_investor, _token, _amount, getTotalStaked(_token));
                    return;
                }
            }
        }

        revert('Could not fill needed amount');
    }

    function withdrawAmount(
        address _token,
        uint256 _amountPending,
        uint256 _feePending,
        address _investor,
        address _feeDestination
    ) internal returns (uint256, uint256) {
        (uint256 totalInvested, uint256[] memory amountList) = getTotalInvestedAndList(_token);
        uint256 amountTotalWithdrawFromInvested = _amountPending;
        uint256 feeTotalFromInvested = _feePending;

        for (uint8 i = 0; i < protocolList.length(); i++) {
            //console.log("    SOL MuchoHub - iteration invested ", amountList[i], totalInvested);
            (_amountPending, _feePending) = withdrawFromProtocol(
                protocolList.at(i),
                _token,
                _investor,
                _feeDestination,
                feeTotalFromInvested,
                amountTotalWithdrawFromInvested,
                _feePending,
                _amountPending,
                amountList[i],
                totalInvested
            );
            //console.log("    SOL MuchoHub - protocol done, pending: ", amountPending);

            //Already filled amount
            if (_amountPending == 0 && _feePending == 0) {
                break;
            }
        }

        return (_amountPending, _feePending);
    }

    function withdrawFromProtocol(
        address _protocol,
        address _token,
        address _investor,
        address _owner,
        uint256 _feeTotal,
        uint256 _amountTotal,
        uint256 _feePending,
        uint256 _amountPending,
        uint256 invProtocol,
        uint256 invTotal
    ) internal returns (uint256, uint256) {
        uint256 feeProtocol = _feeTotal.mul(invProtocol).div(invTotal);
        uint256 amountProtocol = _amountTotal.mul(invProtocol).div(invTotal);
        uint256 amountToWithdraw = (amountProtocol > _amountPending) ? _amountPending : amountProtocol;
        uint256 feeToWithdraw = (feeProtocol > _feePending) ? _feePending : feeProtocol;
        //console.log("    SOL MuchoHub - amount to withdraw ", amountToWithdraw);

        if (amountToWithdraw > 0) IMuchoProtocol(_protocol).withdrawAndSend(_token, amountToWithdraw, _investor);

        if (feeToWithdraw > 0) IMuchoProtocol(_protocol).withdrawAndSend(_token, feeToWithdraw, _owner);

        return (_amountPending.sub(amountToWithdraw), _feePending.sub(feeToWithdraw));
    }

    function refreshInvestment(address _protocol) public onlyOwnerTraderOrAdmin activeProtocol(_protocol) {
        IMuchoProtocol p = IMuchoProtocol(_protocol);
        (address[] memory tokens, uint256[] memory amounts) = p.getAllTokensStaked();
        p.cycleRewards();
        p.refreshInvestment();
        (address[] memory tokensNew, uint256[] memory amountsNew) = p.getAllTokensStaked();

        for (uint16 i = 0; i < tokens.length; i++) {
            bool found = false;
            for (uint16 j = 0; j < tokensNew.length; j++) {
                if (tokens[i] == tokens[j]) {
                    emit InvestmentRefreshed(_protocol, tokens[i], amounts[i], amountsNew[i]);
                    found = true;
                    break;
                }
            }
            if (!found) {
                revert('Cannot find old token in new token list');
            }
        }
    }

    function refreshAllInvestments() external onlyOwnerTraderOrAdmin {
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            refreshInvestment(protocolList.at(i));
        }
        lastFullRefresh = block.timestamp;
    }

    function getDepositFee(address _token, uint256 _amount) external view returns (uint256) {
        require(tokenDefaultInvestment[_token].defined, 'MuchoHub: Investment not defined for the token');

        uint256 fee = 0;
        for (uint256 i = 0; i < tokenDefaultInvestment[_token].parts.length; i++) {
            IMuchoProtocol p = IMuchoProtocol(tokenDefaultInvestment[_token].parts[i].protocol);
            uint256 amountProtocol = _amount.mul(tokenDefaultInvestment[_token].parts[i].percentage).div(10000);
            fee = fee.add(p.getDepositFee(_token, amountProtocol));
        }

        return fee;
    }

    function getWithdrawalFee(address _token, uint256 _amount) external view returns (uint256) {
        require(tokenDefaultInvestment[_token].defined, 'MuchoHub: Investment not defined for the token');

        uint256 fee = 0;
        for (uint256 i = 0; i < tokenDefaultInvestment[_token].parts.length; i++) {
            IMuchoProtocol p = IMuchoProtocol(tokenDefaultInvestment[_token].parts[i].protocol);
            uint256 amountProtocol = _amount.mul(tokenDefaultInvestment[_token].parts[i].percentage).div(10000);
            fee = fee.add(p.getWithdrawalFee(_token, amountProtocol));
        }

        return fee;
    }

    //Expected APR with current investment
    function getExpectedAPR(address _token, uint256 _additionalAmount) external view returns (uint256) {
        require(tokenDefaultInvestment[_token].defined, 'MuchoHub: Investment not defined for the token');

        uint256 ponderatedApr = 0;
        for (uint256 i = 0; i < tokenDefaultInvestment[_token].parts.length; i++) {
            IMuchoProtocol p = IMuchoProtocol(tokenDefaultInvestment[_token].parts[i].protocol);
            uint256 amount = _additionalAmount.mul(tokenDefaultInvestment[_token].parts[i].percentage).div(10000);
            ponderatedApr = ponderatedApr.add(p.getExpectedAPR(_token, amount).mul(amount));
        }

        return ponderatedApr.div(_additionalAmount);
    }

    //Expected APR for a NFT
    function getExpectedNFTAnnualYield() external view returns (uint256) {
        uint256 totalYield = 0;
        for (uint256 i = 0; i < protocolList.length(); i++) {
            IMuchoProtocol p = IMuchoProtocol(protocolList.at(i));
            totalYield = totalYield.add(p.getExpectedNFTAnnualYield());
        }

        return totalYield;
    }

    function protocols() external view returns (address[] memory) {
        address[] memory list = new address[](protocolList.length());
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            list[i] = protocolList.at(i);
        }

        return list;
    }

    function getTotalNotInvested(address _token) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            total = total.add(IMuchoProtocol(protocolList.at(i)).getTokenNotInvested(_token));
        }
        return total;
    }

    function getTotalStaked(address _token) public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            total = total.add(IMuchoProtocol(protocolList.at(i)).getTokenStaked(_token));
        }
        return total;
    }

    function getTokenDefaults(address _token) external view returns (InvestmentPart[] memory) {
        require(tokenDefaultInvestment[_token].defined, 'MuchoHub: Default investment not defined for token');
        return tokenDefaultInvestment[_token].parts;
    }

    function getTotalInvestedAndList(address _token) internal view returns (uint256, uint256[] memory) {
        uint256 total = 0;
        uint256[] memory amounts = new uint256[](protocolList.length());
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            IMuchoProtocol prot = IMuchoProtocol(protocolList.at(i));
            amounts[i] = prot.getTokenInvested(_token);
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

    function getCurrentInvestment(address _token) external view returns (InvestmentAmountPartition memory) {
        InvestmentAmountPart[] memory parts = new InvestmentAmountPart[](protocolList.length());
        for (uint256 i = 0; i < protocolList.length(); i = i.add(1)) {
            parts[i].protocol = protocolList.at(i);
            parts[i].amount = IMuchoProtocol(protocolList.at(i)).getTokenStaked(_token);
        }
        InvestmentAmountPartition memory out = InvestmentAmountPartition({parts: parts});
        return out;
    }
}
