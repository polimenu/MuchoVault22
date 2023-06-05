// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IMuchoBadgeManager.sol";



/*----------------------------Swaps between muchoTokens handling------------------------------*/
library MuchoSwap {

    using SafeMath for uint256;

    //MuchoBadge Interaction
    IMuchoBadgeManager private badgeManager = IMuchoBadgeManager(0xC439d29ee3C7fa237da928AD3A3D6aEcA9aA0717);

    // Basis points fee for swapping muchoTokens
    uint256 private bpSwapMuchoTokensFee = 25;


    // Same (special fee) for MuchoBadge holders:
    struct MuchoBadgeSpecialFee{  uint256 fee;  bool exists; }
    mapping(uint256 => MuchoBadgeSpecialFee) public bpSwapMuchoTokensFeeForBadgeHolders;

    function setSwapMuchoTokensFeeForPlan(uint256 _planId, uint256 _percent) external onlyOwner {
        require(_percent < 1000 && _percent >= 0, "not in range");
        require(_planId > 0, "not valid plan");
        bpSwapMuchoTokensFeeForBadgeHolders[_planId] = MuchoBadgeSpecialFee({fee : _percent, exists: true});
    }
    function removeSwapMuchoTokensFeeForPlan(uint256 _planId) external onlyOwner {
        require(_planId > 0, "not valid plan");
        bpSwapMuchoTokensFeeForBadgeHolders[_planId].exists = false;
    }
    

    //Gets the swap fee between muchoTokens for a user, depending on the possesion of NFT
    function getSwapFee(address _user) public view returns(uint256){
        require(_user != address(0), "Not a valid user");
        uint256 swapFee = bpSwapMuchoTokensFee;
        IMuchoBadgeManager.Plan[] memory plans = badgeManager.activePlansForUser(_user);
        for(uint i = 0; i < plans.length; i = i.add(1)){
            uint256 id = plans[i].id;
            if(bpSwapMuchoTokensFeeForBadgeHolders[id].exists && bpSwapMuchoTokensFeeForBadgeHolders[id].fee < swapFee)
                swapFee = bpSwapMuchoTokensFeeForBadgeHolders[id].fee;
        }

        return swapFee;
    }

    //Returns the amount out (destination token) and to the owner (source token) for the swap
    function getOwnerFeeDestinationAmountMuchoTokenExchange(uint256 _totalSourceStaked, 
                                            uint256 _totalMuchoSourceSupply,
                                            uint256 _amountSourceMToken, 
                                            uint256 _totalDestStaked,
                                            uint256 _totalMuchoDestSupply,
                                            uint256 _sourcePrice,
                                            uint256 _targetPrice ) 
                                                    public view returns(uint256, uint256){
        require(_amountSourceMToken > 0, "Insufficent amount");
        uint256 amountSourceForOwner = 0;
        {
            //Calc swap fee
            uint256 swapFee = getSwapFee(msg.sender);

            //Mint swap fee tokens to owner:
            if(swapFee > 0){
                amountSourceForOwner = _amountSourceMToken.mul(swapFee).div(10000);
                _amountSourceMToken = _amountSourceMToken.sub(amountSourceForOwner);
            }
        }

        uint256 amountTargetForUser = 0;
        {
            //muchotoken to real token exchange for source
            uint256 sMTokenExchange = _totalSourceStaked.mul(10**6);
            sMTokenExchange = sMTokenExchange.div(_totalMuchoSourceSupply);
            amountTargetForUser = _amountSourceMToken
                                        .mul(sMTokenExchange); //muchotoken to real token exchange for source
        }
        {
            //muchotoken to real token exchange for target
            uint256 dMTokenExchange = _totalDestStaked.mul(10**6).div(_totalMuchoDestSupply);
            //uint256 sourcePrice = priceFeed.getPrice(address(vaultInfo[_sourceVaultId].depositToken));
            amountTargetForUser = amountTargetForUser.mul(_sourcePrice) //source deposit token in usd
                                        .div(_targetPrice/*priceFeed.getPrice(address(vaultInfo[_destVaultId].depositToken))*/) //target deposit token in usd
                                        .div(dMTokenExchange);
        }
        return (amountSourceForOwner, amountTargetForUser);
    }

}