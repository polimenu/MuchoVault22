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

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./MuchoRoles.sol";
import "../interfaces/IMuchoRewardRouter.sol";
import "../interfaces/IMuchoBadgeManager.sol";
import "../interfaces/IMuchoToken.sol";
import "../interfaces/IMuchoVault.sol";



contract MuchoRewardRouter is ReentrancyGuard, IMuchoRewardRouter, MuchoRoles {

    using SafeERC20 for IERC20;
    using SafeERC20 for IMuchoToken;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;


    //NFT Plan ID allowed get rewards
    EnumerableSet.UintSet planList;

    //Allows to power up rewards for some plans
    mapping(uint256 => uint) public planMultiplier;

    //List of users
    EnumerableSet.AddressSet userAddressList;

    //Reward tokens
    EnumerableSet.AddressSet rewardTokenList;

    //Badge manager and setter
    IMuchoBadgeManager public badgeManager = IMuchoBadgeManager(0xC439d29ee3C7fa237da928AD3A3D6aEcA9aA0717);
    function setBadgeManager(address _bm) public onlyOwner{ badgeManager = IMuchoBadgeManager(_bm); }

    //MuchoVaultV2 and setter
    IMuchoVault public muchoVault = IMuchoVault(address(0)); //Pending to assign actual address
    function setMuchoVault(address _mv) public onlyOwner{ muchoVault = IMuchoVault(_mv); }

    //Earnings address to send the "rests" when i.e. no NFT holders
    address public earningsAddress = address(0);
    function setEarningsAddress(address _ea) public onlyOwner{ earningsAddress = _ea; }

    //List of rewards
    mapping(address => mapping(address => uint256)) public rewards;


    /*----------------------USER HANDLING OWNER FUNCTIONS---------------------*/

    //Checks if a user exists and adds it to the list
    function addUserIfNotExists(address _user) public onlyOwner {
        userAddressList.add(_user);
        emit UserAdded(_user);
    }
    
    //Removes a user if exists in the lust
    function removeUserIfExists(address _user) public onlyOwner {
        userAddressList.remove(_user);
        emit UserRemoved(_user);
    }
    

    /*----------------------NFT PLANS AND MULTIPLIER SETTINGS OWNER FUNCTIONS---------------------*/

    //Adds a plan with benefits
    function addPlanId(uint256 _planId, uint _multiplier) public onlyOwner {
        require(!planList.contains(_planId), "Plan already added");

        planList.add(_planId);
        planMultiplier[_planId] = _multiplier;

        emit PlanAdded(_planId, _multiplier);
    }
    
    //Removes a plan benefits
    function removePlanId(uint256 _planId) public onlyOwner {
        require(planList.contains(_planId), "Plan not found");
        planList.remove(_planId);
        delete planMultiplier[_planId];
        emit PlanRemoved(_planId);
    }

    //Changes the multiplier for a plan
    function setMultiplier(uint256 _planId, uint _multiplier) public onlyOwner {
        require(planList.contains(_planId), "Plan not found");
        planMultiplier[_planId] = _multiplier;
        emit MultiplierChanged(_planId, _multiplier);
    }

    
    /*----------------------PUBLIC CORE FUNCTIONS---------------------*/

    //Deposit the rewards and split among the users
    function depositRewards(address _token, uint256 _amount) public nonReentrant{
        //console.log("    SOL-***depositRewards***");
        IERC20 rewardToken = IERC20(_token);
        require(rewardToken.balanceOf(msg.sender) >= _amount, "Not enough balance");
        require(rewardToken.allowance(msg.sender, address(this)) >= _amount, "Not enough allowance");
        
        //console.log("    SOL - getting total USD from nft holders");
        (uint256 totalUSD, uint256[] memory usersUSD) = getTotalAndUsersUSDValueWithMultiplier();
        //console.log("    SOL - total USD from nft holders", totalUSD);

        if(totalUSD > 0){ //Get the money
            //console.log("    SOL - getting the money for NFT holders");
            rewardToken.safeTransferFrom(msg.sender, address(this), _amount);

            //Split among the users
            for(uint i = 0; i < userAddressList.length(); i = i.add(1)){
                uint ponderatedUserUSD = usersUSD[i];
                //console.log("       SOL - user amount", usersUSD[i]);

                if(ponderatedUserUSD > 0){
                    uint256 userAmount = _amount.mul(ponderatedUserUSD).div(totalUSD);
                    rewards[userAddressList.at(i)][_token] = rewards[userAddressList.at(i)][_token].add(userAmount);
                    emit RewardsUserEarned(_token, msg.sender, userAmount);
                }

            }

            rewardTokenList.add(_token);
            emit RewardsDeposited(_token, _amount);
        }
        else{
            //console.log("    SOL - no nft holders, sending to the earnings address");
            rewardToken.safeTransferFrom(msg.sender, earningsAddress, _amount);
            emit RewardsNotDeposited(_token, _amount);
        }
        //console.log("    SOL-***END depositRewards***");
    }

    //For a plan, gets the current amount ponderation (basis points) for a new deposit. This will be needed to calculate estimated APR that plan's users are getting in avg
    function getPlanPonderation(uint256 _planId) public view returns(uint256){
        (uint256 planAmountPonderated, uint256 totalUSD) = getTotalAndPlanUSDValueWithMultiplier(_planId);

        return planAmountPonderated.mul(10000).div(totalUSD);
    }


    //Withdraws the rewards the user has for a token
    function withdrawToken(address _token) public nonReentrant returns(uint256){
        IERC20 rewardToken = IERC20(_token);
        uint amount = rewards[msg.sender][_token];
        require(amount > 0, "No rewards");

        //zero balance
        rewards[msg.sender][_token] = 0;

        //Get the money
        rewardToken.safeTransfer(msg.sender, amount);

        //if no balance left, remove token from list
        if(rewardToken.balanceOf(address(this)) == 0)
            rewardTokenList.remove(_token);

        emit Withdrawn(_token, amount);

        return amount;
    }


    //Withdraws the rewards the user has for every token
    function withdraw() public {
        for(uint256 i = 0; i < rewardTokenList.length(); i = i.add(1)){
            withdrawToken(rewardTokenList.at(i));
        }
    }

    //Gets the best plan multiplier for the user
    function getUserMultiplierAndPlan(address _user) public view returns(uint, uint256){
        uint multiplier = 0; uint256 plan = 0;
        IMuchoBadgeManager.Plan[] memory nfts = badgeManager.activePlansForUser(_user);
        for(uint i = 0; i < nfts.length; i = i.add(1)){
            if(planMultiplier[nfts[i].id] > multiplier){
                plan = nfts[i].id;
                multiplier = planMultiplier[plan];
            }
        }

        return (multiplier, plan);
    }

    /*----------------------INTERNAL FUNCTIONS---------------------*/

    /*
        Loops for every user and returns:
            -every user's usd deposited, ponderated with his plan multiplier
            -total usd ponderated with plans multipliers
    */
    function getTotalAndUsersUSDValueWithMultiplier() internal view returns(uint256, uint256[] memory){
        uint256[] memory uUSD = new uint256[](userAddressList.length());
        uint256 totalUSD = 0;

        for(uint i = 0; i < userAddressList.length(); i = i.add(1)){
            (uint multiplier, ) = getUserMultiplierAndPlan(userAddressList.at(i));

            if(multiplier > 0){
                uint256 userUSD = muchoVault.investorTotalUSD(userAddressList.at(i)).mul(multiplier);
                uUSD[i] = userUSD;
                totalUSD = totalUSD.add(userUSD);
            }
            else
                uUSD[i] = 0;

        }


        return (totalUSD, uUSD);
    }

    /*
            For a given planId, loops for every user and returns:
                -total usd ponderated with plans multiplier, for the planId given
                -total usd ponderated with plans multipliers
    */
    function getTotalAndPlanUSDValueWithMultiplier(uint256 _planId) internal view returns(uint256, uint256){
        uint256 planValue = 0;
        uint256 totalValue = 0;
        for(uint i = 0; i < userAddressList.length(); i = i.add(1)){
            (uint multiplier, uint256 plan) = getUserMultiplierAndPlan(userAddressList.at(i));

            if(multiplier > 0){
                uint256 userUSD = muchoVault.investorTotalUSD(userAddressList.at(i));
                if(plan == _planId)
                    planValue = planValue.add(userUSD);

                totalValue = totalValue.add(userUSD);
            }

        }

        return (totalValue, planValue);
    }

    //Same as getTotalAndUsersUSDValueWithMultiplier, but only returns the total usd ponderated
    function getTotalPonderatedInvestment() public view returns(uint256){
        uint256 totalUSD = 0;
        for(uint i = 0; i < userAddressList.length(); i = i.add(1)){
            (uint multiplier, ) = getUserMultiplierAndPlan(userAddressList.at(i));

            if(multiplier > 0){
                uint256 userUSD = muchoVault.investorTotalUSD(userAddressList.at(i)).mul(multiplier);
                totalUSD = totalUSD.add(userUSD);
            }

        }

        return totalUSD;
    }

}