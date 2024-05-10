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

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import './MuchoRoles.sol';
import '../interfaces/IMuchoRewardRouterV2.sol';
import '../interfaces/IMuchoBadgeManager.sol';
import '../interfaces/IMuchoToken.sol';
import '../interfaces/IMuchoVault.sol';

contract MuchoRewardRouterV2 is ReentrancyGuard, IMuchoRewardRouterV2, MuchoRoles {
    using SafeERC20 for IERC20;
    using SafeERC20 for IMuchoToken;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserAmount {
        address user;
        uint256 amount;
    }

    //Expiration time and setter
    uint256 public expirationTime = 90 * 24 * 3600;

    function setExpirationTime(uint256 _newTime) external onlyAdmin {
        expirationTime = _newTime;
    }

    //Reward tokens
    EnumerableSet.AddressSet rewardTokenList;

    function addRewardToken(address _token) external onlyAdmin {
        rewardTokenList.add(_token);
    }

    function removeRewardToken(address _token) external onlyAdmin {
        rewardTokenList.remove(_token);
    }

    //List of rewards
    mapping(address => mapping(address => uint256)) public rewards;

    //List of last withdrawns
    mapping(address => uint256) public lastWithdrawn;

    /*----------------------OWNER FUNCTIONS---------------------*/

    function bulkAssignReward(address _token, UserAmount[] calldata _usersAmounts) external onlyTraderOrAdmin nonReentrant {
        uint256 totalAmount = rewards[address(0)][_token];

        if (totalAmount > 0) {
            for (uint256 i = 0; i < _usersAmounts.length; i++) {
                require(_usersAmounts[i].amount <= totalAmount, 'Assigning more than existing unassigned rewards');

                addRewardToUser(_token, _usersAmounts[i].user, _usersAmounts[i].amount);
                totalAmount -= _usersAmounts[i].amount;
            }

            rewards[address(0)][_token] = totalAmount;
        }
    }

    //Deposit reward for a user
    function depositReward(address _token, UserAmount calldata _userAmount) external onlyTraderOrAdmin nonReentrant {
        //console.log("    SOL-***depositReward***");
        IERC20 rewardToken = IERC20(_token);
        require(rewardToken.balanceOf(msg.sender) >= _userAmount.amount, 'Not enough balance');
        require(rewardToken.allowance(msg.sender, address(this)) >= _userAmount.amount, 'Not enough allowance');

        //Get the funds
        rewardToken.safeTransferFrom(msg.sender, address(this), _userAmount.amount);

        //Add to user
        addRewardToUser(_token, _userAmount.user, _userAmount.amount);
    }

    //Bulk deposit rewards for users
    function bulkDepositReward(address _token, UserAmount[] calldata _usersAmounts) external onlyTraderOrAdmin nonReentrant {
        //console.log("    SOL-***depositReward***");
        IERC20 rewardToken = IERC20(_token);
        uint256 totalAmount = 0;

        //Add to users and calc total amount
        for (uint256 i = 0; i < _usersAmounts.length; i++) {
            addRewardToUser(_token, _usersAmounts[i].user, _usersAmounts[i].amount);
            totalAmount += _usersAmounts[i].amount;
        }

        require(rewardToken.balanceOf(msg.sender) >= totalAmount, 'Not enough balance');
        require(rewardToken.allowance(msg.sender, address(this)) >= totalAmount, 'Not enough allowance');

        //Get the funds
        rewardToken.safeTransferFrom(msg.sender, address(this), totalAmount);
    }

    function depositRewards(address _token, uint256 _amount) external onlyOwnerTraderOrAdmin nonReentrant {
        IERC20 rewardToken = IERC20(_token);
        require(rewardToken.balanceOf(msg.sender) >= _amount, 'Not enough balance');
        require(rewardToken.allowance(msg.sender, address(this)) >= _amount, 'Not enough allowance');

        //Get the funds
        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);

        //Increase not assigned rewards
        addRewardToUser(_token, address(0), _amount);
    }

    function retrieveExpiredRewards(address _user, address _token, uint256 _amount) external onlyTraderOrAdmin nonReentrant {
        require(rewardsExpired(_user), 'Rewards not expired');
        require(rewards[_user][_token] >= _amount, 'Not enough rewards');

        //balance
        rewards[_user][_token] -= _amount;

        //Get the money
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function retrieveFullRewards(address _user, address _token) external onlyTraderOrAdmin nonReentrant {
        require(rewardsExpired(_user), 'Rewards not expired');
        require(rewards[_user][_token] > 0, 'Not enough rewards');

        //Get the money
        IERC20(_token).safeTransfer(msg.sender, rewards[_user][_token]);

        //balance
        rewards[_user][_token] = 0;
    }

    /*---------------------VIEWS------------------------*/
    function rewardsExpired(address _user) public view returns (bool expired) {
        expired = (lastWithdrawn[_user] != 0) && (block.timestamp.sub(lastWithdrawn[_user]) > expirationTime);
    }

    /*----------------------PUBLIC CORE FUNCTIONS---------------------*/

    //Withdraws the rewards the user has for a token
    function withdrawToken(address _token) public nonReentrant returns (uint256) {
        require(msg.sender != address(0), 'Not valid address');
        IERC20 rewardToken = IERC20(_token);
        uint amount = rewards[msg.sender][_token];
        require(amount > 0, 'No rewards');

        //zero balance
        rewards[msg.sender][_token] = 0;
        lastWithdrawn[msg.sender] = block.timestamp;

        //Get the money
        rewardToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(_token, amount);

        return amount;
    }

    //Withdraws the rewards the user has for every token
    function withdraw() external {
        for (uint256 i = 0; i < rewardTokenList.length(); i = i.add(1)) {
            withdrawToken(rewardTokenList.at(i));
        }
    }

    /*----------------------INTERNAL FUNCTIONS---------------------*/

    function addRewardToUser(address _token, address _user, uint256 _amount) internal {
        rewards[_user][_token] = rewards[_user][_token].add(_amount);
        emit RewardDeposited(_token, _user, _amount);

        if (lastWithdrawn[_user] == 0) {
            lastWithdrawn[_user] = block.timestamp;
        }
    }
}
