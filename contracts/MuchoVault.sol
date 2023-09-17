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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IMuchoVault.sol";
import "../interfaces/IMuchoHub.sol";
import "../interfaces/IMuchoBadgeManager.sol";
import "../interfaces/IPriceFeed.sol";
import "./MuchoRoles.sol";
import "../lib/UintSafe.sol";

contract MuchoVault is IMuchoVault, MuchoRoles, ReentrancyGuard{

    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for uint8;
    using UintSafe for uint256;

    VaultInfo[] private vaultInfo;

    /*-------------------------TYPES---------------------------------------------*/
    // Same (special fee) for MuchoBadge NFT holders:
    struct MuchoBadgeSpecialFee{  
        uint256 fee;  
        bool exists; 
    }

    /*--------------------------CONTRACTS---------------------------------------*/

    //HUB for handling investment in the different protocols:
    IMuchoHub public muchoHub = IMuchoHub(address(0));
    function setMuchoHub(address _contract) external onlyAdmin{ 
        muchoHub = IMuchoHub(_contract);
        emit MuchoHubChanged(_contract); 
    }

    //Price feed to calculate USD values:
    IPriceFeed public priceFeed = IPriceFeed(0x846ecf0462981CC0f2674f14be6Da2056Fc16bDA);
    function setPriceFeed(address _contract) external onlyAdmin{ 
        priceFeed = IPriceFeed(_contract);
        emit PriceFeedChanged(_contract); 
    }

    //Badge Manager to get NFT holder attributes:
    IMuchoBadgeManager public badgeManager = IMuchoBadgeManager(0xC439d29ee3C7fa237da928AD3A3D6aEcA9aA0717);
    function setBadgeManager(address _contract) external onlyAdmin { 
        badgeManager = IMuchoBadgeManager(_contract);
        emit BadgeManagerChanged(_contract);
    }

    //Address where we send profits from fees:
    address public earningsAddress = 0x829C145cE54A7f8c9302CD728310fdD6950B3e16;
    function setEarningsAddress(address _addr) external onlyAdmin{ 
        earningsAddress = _addr; 
        emit EarningsAddressChanged(_addr);
    }


    /*--------------------------PARAMETERS--------------------------------------*/

    //Maximum amount a user with NFT Plan can invest
    mapping(uint256 => mapping(uint256 => uint256)) maxDepositUserPlan;
    function setMaxDepositUserForPlan(uint256 _vaultId, uint256 _planId, uint256 _amount) external onlyTraderOrAdmin{
        maxDepositUserPlan[_vaultId][_planId] = _amount;
    }
    function getMaxDepositUserForPlan(uint256 _vaultId, uint256 _planId) external view returns(uint256){
        return maxDepositUserPlan[_vaultId][_planId];
    }

    /*---------------------------------MODIFIERS and CHECKERS---------------------------------*/
    //Validates a vault ID
    modifier validVault(uint _id){
        require(_id < vaultInfo.length, "MuchoVaultV2.validVault: not valid vault id");
        _;
    }

    //Checks if there is a vault for the specified token
    function checkDuplicate(IERC20 _depositToken, IMuchoToken _muchoToken) internal view returns(bool) {
        for (uint256 i = 0; i < vaultInfo.length; ++i){
            if (vaultInfo[i].depositToken == _depositToken || vaultInfo[i].muchoToken == _muchoToken){
                return false;
            }        
        }
        return true;
    }

    /*----------------------------------VAULTS SETUP FUNCTIONS-----------------------------------------*/

    //Adds a vault:
    function addVault(IERC20Metadata _depositToken, IMuchoToken _muchoToken) external onlyAdmin returns(uint8){
        require(checkDuplicate(_depositToken, _muchoToken), "MuchoVaultV2.addVault: vault for that deposit or mucho token already exists");
        require(_depositToken.decimals() == _muchoToken.decimals(), "MuchoVaultV2.addVault: deposit and mucho token decimals cannot differ");

        vaultInfo.push(VaultInfo({
            depositToken: _depositToken,
            muchoToken: _muchoToken,
            lastUpdate: block.timestamp, 
            stakable: true,
            withdrawable: true,
            depositFee: 0,
            withdrawFee: 0,
            maxDepositUser: 10**30,
            maxCap: 0
        }));

        emit VaultAdded(_depositToken, _muchoToken);

        return uint8(vaultInfo.length.sub(1));
    }

    //Sets maximum amount to deposit:
    function setMaxCap(uint8 _vaultId, uint256 _max) external onlyTraderOrAdmin validVault(_vaultId){
        vaultInfo[_vaultId].maxCap = _max;
    }

    //Sets maximum amount to deposit for a user:
    function setMaxDepositUser(uint8 _vaultId, uint256 _max) external onlyTraderOrAdmin validVault(_vaultId){
        vaultInfo[_vaultId].maxDepositUser = _max;
    }

    //Sets a deposit fee for a vault:
    function setDepositFee(uint8 _vaultId, uint16 _fee) external onlyTraderOrAdmin validVault(_vaultId){
        require(_fee < 500, "MuchoVault: Max deposit fee exceeded");
        vaultInfo[_vaultId].depositFee = _fee;
        emit DepositFeeChanged(_vaultId, _fee);
    }

    //Sets a withdraw fee for a vault:
    function setWithdrawFee(uint8 _vaultId, uint16 _fee) external onlyTraderOrAdmin validVault(_vaultId){
        require(_fee < 100, "MuchoVault: Max withdraw fee exceeded");
        vaultInfo[_vaultId].withdrawFee = _fee;
        emit WithdrawFeeChanged(_vaultId, _fee);
    }

    //Opens or closes a vault for deposits:
    function setOpenVault(uint8 _vaultId, bool open) public onlyTraderOrAdmin validVault(_vaultId) {
        vaultInfo[_vaultId].stakable = open;
        if(open)
            emit VaultOpen(_vaultId);
        else
            emit VaultClose(_vaultId);
    }

    //Opens or closes ALL vaults for deposits:
    function setOpenAllVault(bool open) external onlyTraderOrAdmin {
        for (uint8 _vaultId = 0; _vaultId < vaultInfo.length; ++ _vaultId){
            setOpenVault(_vaultId, open);
        }
    }

    //Opens or closes a vault for deposits:
    function setWithdrawableVault(uint8 _vaultId, bool open) public onlyTraderOrAdmin validVault(_vaultId) {
        vaultInfo[_vaultId].withdrawable = open;
        if(open)
            emit VaultWithdrawOpen(_vaultId);
        else
            emit VaultWithdrawClose(_vaultId);
    }

    //Opens or closes ALL vaults for deposits:
    function setWithdrawableAllVault(bool open) external onlyTraderOrAdmin {
        for (uint8 _vaultId = 0; _vaultId < vaultInfo.length; ++ _vaultId){
            setWithdrawableVault(_vaultId, open);
        }
    }

    // Refresh Investment and update all vaults:
    function refreshAndUpdateAllVaults() external onlyTraderOrAdmin {
        muchoHub.refreshAllInvestments();
    }

    /*----------------------------CORE: User deposit and withdraw------------------------------*/
    
    //Deposits an amount in a vault
    function deposit(uint8 _vaultId, uint256 _amount) external validVault(_vaultId) nonReentrant {
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        IERC20 dToken = vaultInfo[_vaultId].depositToken;


        /*console.log("    SOL - DEPOSITING");
        console.log("    SOL - Sender and balance", msg.sender, dToken.balanceOf(msg.sender));
        console.log("    SOL - amount", _amount);*/
        
        require(_amount != 0, "MuchoVaultV2.deposit: Insufficent amount");
        require(msg.sender != address(0), "MuchoVaultV2.deposit: address is not valid");
        require(_amount <= dToken.balanceOf(msg.sender), "MuchoVaultV2.deposit: balance too low" );
        require(vaultInfo[_vaultId].stakable, "MuchoVaultV2.deposit: not stakable");
        require(vaultInfo[_vaultId].maxCap == 0 || vaultInfo[_vaultId].maxCap >= _amount.add(vaultTotalStaked(_vaultId)), "MuchoVaultV2.deposit: depositing more than max allowed in total");
        uint256 wantedDeposit = _amount.add(investorVaultTotalStaked(_vaultId, msg.sender));
        require(wantedDeposit <= investorMaxAllowedDeposit(_vaultId, msg.sender), "MuchoVaultV2.deposit: depositing more than max allowed per user");
     
        // Gets the amount of deposit token locked in the contract
        uint256 totalStakedTokens = vaultTotalStaked(_vaultId);

        // Gets the amount of muchoToken in existence
        uint256 totalShares = mToken.totalSupply();

        // Remove the deposit fee and calc amount after fee
        uint256 ownerDepositFee = _amount.mul(vaultInfo[_vaultId].depositFee).div(10000);
        uint256 amountAfterOwnerFee = _amount.sub(ownerDepositFee);
        uint256 amountAfterAllFees = _amount.sub(getDepositFee(_vaultId, _amount));

        /*console.log("    SOL - depositFee", vaultInfo[_vaultId].depositFee);
        console.log("    SOL - ownerDepositFee", ownerDepositFee);
        console.log("    SOL - amountAfterFee", amountAfterFee);*/

        // If no muchoToken exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalStakedTokens == 0) {
            mToken.mint(msg.sender, amountAfterAllFees);
        } 
        // Calculate and mint the amount of muchoToken the depositToken is worth. The ratio will change overtime with APR
        else {
            uint256 what = amountAfterAllFees.mul(totalShares).div(totalStakedTokens);
            mToken.mint(msg.sender, what);
        }

        //console.log("    SOL - TOTAL STAKED AFTER DEP 0", vaultInfo[_vaultId].totalStaked);
        //console.log("    SOL - EXECUTING DEPOSIT FROM IN HUB");
        muchoHub.depositFrom(msg.sender, address(dToken), amountAfterOwnerFee, ownerDepositFee, earningsAddress);
        //console.log("    SOL - TOTAL STAKED AFTER DEP 1", vaultInfo[_vaultId].totalStaked);
        //console.log("    SOL - EXECUTING UPDATE VAULT");
        //console.log("    SOL - TOTAL STAKED AFTER DEP 2", vaultInfo[_vaultId].totalStaked);

        emit Deposited(msg.sender, _vaultId, _amount, vaultTotalStaked(_vaultId));
    }

    //Withdraws from a vault. The user should have muschoTokens that will be burnt
    function withdraw(uint8 _vaultId, uint256 _share) external validVault(_vaultId) nonReentrant {
        //console.log("    SOL - WITHDRAW!!!");
        require(vaultInfo[_vaultId].withdrawable, "MuchoVault: not withdrawable");

        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        IERC20 dToken = vaultInfo[_vaultId].depositToken;

        require(_share != 0, "MuchoVaultV2.withdraw: Insufficient amount");
        require(msg.sender != address(0), "MuchoVaultV2.withdraw: address is not valid");
        require(_share <= mToken.balanceOf(msg.sender), "MuchoVaultV2.withdraw: balance too low");

        // Calculates the amount of depositToken the muchoToken is worth
        uint256 amountOut = _share.mul(vaultTotalStaked(_vaultId)).div(mToken.totalSupply());

        mToken.burn(msg.sender, _share);

        // Calculates withdraw fee:
        uint256 ownerWithdrawFee = amountOut.mul(vaultInfo[_vaultId].withdrawFee).div(10000);
        amountOut = amountOut.sub(ownerWithdrawFee);

        //console.log("    SOL - amountOut, ownerFee", amountOut, ownerWithdrawFee);

        muchoHub.withdrawFrom(msg.sender, address(dToken), amountOut, ownerWithdrawFee, earningsAddress);


        emit Withdrawn(msg.sender, _vaultId, amountOut, _share, vaultTotalStaked(_vaultId));
    }


    /*---------------------------------INFO VIEWS---------------------------------------*/

    //Gets the deposit fee amount, adding owner's deposit fee (in this contract) + protocol's one
    function getDepositFee(uint8 _vaultId, uint256 _amount) public view returns(uint256){
        uint256 fee = _amount.mul(vaultInfo[_vaultId].depositFee).div(10000);
        return fee.add(muchoHub.getDepositFee(address(vaultInfo[_vaultId].depositToken), _amount.sub(fee)));
    }

    //Gets the withdraw fee amount, adding owner's withdraw fee (in this contract) + protocol's one
    function getWithdrawalFee(uint8 _vaultId, uint256 _amount) external view returns(uint256){
        uint256 fee = muchoHub.getWithdrawalFee(address(vaultInfo[_vaultId].depositToken), _amount);
        return fee.add(_amount.sub(fee).mul(vaultInfo[_vaultId].withdrawFee).div(10000));
    }

    //Gets the expected APR if we add an amount of token
    function getExpectedAPR(uint8 _vaultId, uint256 _additionalAmount) external view returns(uint256){
        return muchoHub.getExpectedAPR(address(vaultInfo[_vaultId].depositToken), _additionalAmount);
    }

    //Displays total amount of staked tokens in a vault:
    function vaultTotalStaked(uint8 _vaultId) validVault(_vaultId) public view returns(uint256) {
        return muchoHub.getTotalStaked(address(vaultInfo[_vaultId].depositToken));
    }
    

    //Displays total amount a user has staked in a vault:
    function investorVaultTotalStaked(uint8 _vaultId, address _address) validVault(_vaultId) public view returns(uint256) {
        require(_address != address(0), "MuchoVaultV2.displayStakedBalance: No valid address");
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        uint256 totalShares = mToken.totalSupply();
        if(totalShares == 0) return 0;
        uint256 amountOut = mToken.balanceOf(_address).mul(vaultTotalStaked(_vaultId)).div(totalShares);
        return amountOut;
    }

    //Maximum amount of token allowed to deposit for user:
    function investorMaxAllowedDeposit(uint8 _vaultId, address _user) validVault(_vaultId) public view returns(uint256){
        uint256 maxAllowed = vaultInfo[_vaultId].maxDepositUser;
        IMuchoBadgeManager.Plan[] memory plans = badgeManager.activePlansForUser(_user);
        for(uint i = 0; i < plans.length; i = i.add(1)){
            uint256 id = plans[i].id;
            if(maxDepositUserPlan[_vaultId][id] > maxAllowed)
                maxAllowed = maxDepositUserPlan[_vaultId][id];
        }

        return maxAllowed;
    }

    //Price Muchotoken vs "real" token:
    function muchoTokenToDepositTokenPrice(uint8 _vaultId) validVault(_vaultId) external view returns(uint256) {
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        uint256 totalShares = mToken.totalSupply();
        uint256 amountOut = vaultTotalStaked(_vaultId).mul(10**18).div(totalShares);
        return amountOut;
    }

    //Total USD in a vault (18 decimals):
    function vaultTotalUSD(uint8 _vaultId) validVault(_vaultId) public view returns(uint256) {
         return getUSD(vaultInfo[_vaultId].depositToken, vaultTotalStaked(_vaultId));
    }

    //Total USD an investor has in a vault:
    function investorVaultTotalUSD(uint8 _vaultId, address _user) validVault(_vaultId) public view returns(uint256) {
        require(_user != address(0), "MuchoVaultV2.totalUserVaultUSD: Invalid address");
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        uint256 mTokenUser = mToken.balanceOf(_user);
        uint256 mTokenTotal = mToken.totalSupply();

        if(mTokenUser == 0 || mTokenTotal == 0)
            return 0;

        return getUSD(vaultInfo[_vaultId].depositToken, vaultTotalStaked(_vaultId).mul(mTokenUser).div(mTokenTotal));
    }

    //Total USD an investor has in all vaults:
    function investorTotalUSD(address _user) public view returns(uint256){
        require(_user != address(0), "MuchoVaultV2.totalUserUSD: Invalid address");
        uint256 total = 0;
         for (uint8 i = 0; i < vaultInfo.length; ++i){
            total = total.add(investorVaultTotalUSD(i, _user));
         }

         return total;
    }

    //Protocol TVL in USD:
    function allVaultsTotalUSD() public view returns(uint256) {
         uint256 total = 0;
         for (uint8 i = 0; i < vaultInfo.length; ++i){
            total = total.add(vaultTotalUSD(i));
         }

         return total;
    }

    //Gets a vault descriptive:
    function getVaultInfo(uint8 _vaultId) external view validVault(_vaultId) returns(VaultInfo memory){
        return vaultInfo[_vaultId];
    }
    
    //gets usd amount with 18 decimals for a erc20 token and amount
    function getUSD(IERC20Metadata _token, uint256 _amount) internal view returns(uint256){
        uint256 tokenPrice = priceFeed.getPrice(address(_token));
        uint256 totalUSD = tokenPrice.mul(_amount).div(10**30); //as price feed uses 30 decimals
        uint256 decimals = _token.decimals();
        if(decimals > 18){
            totalUSD = totalUSD.div(10 ** (decimals - 18));
        }
        else if(decimals < 18){
            totalUSD = totalUSD.mul(10 ** (18 - decimals));
        }

        return totalUSD;
    }

}