// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IMuchoVault.sol";
import "../interfaces/IMuchoHub.sol";
import "../interfaces/IMuchoBadgeManager.sol";
import "../interfaces/IPriceFeed.sol";
import "./MuchoRoles.sol";
import "../lib/UintSafe.sol";
import "../lib/AprInfo.sol";
import "hardhat/console.sol";

contract MuchoVault is IMuchoVault, MuchoRoles, ReentrancyGuard{

    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for uint8;
    using UintSafe for uint256;
    using AprLib for AprInfo;

    VaultInfo[] private vaultInfo;
    AprInfo[] private aprInfo;

    /*-------------------------TYPES---------------------------------------------*/
    // Same (special fee) for MuchoBadge NFT holders:
    struct MuchoBadgeSpecialFee{  
        uint256 fee;  
        bool exists; 
    }

    /*--------------------------CONTRACTS---------------------------------------*/

    //HUB for handling investment in the different protocols:
    IMuchoHub muchoHub = IMuchoHub(0x0000000000000000000000000000000000000000);
    function setMuchoHub(address _contract) external onlyAdmin{ muchoHub = IMuchoHub(_contract); }

    //Price feed to calculate USD values:
    IPriceFeed priceFeed = IPriceFeed(0x0000000000000000000000000000000000000000);
    function setPriceFeed(address _contract) external onlyAdmin{ priceFeed = IPriceFeed(_contract); }

    //Badge Manager to get NFT holder attributes:
    IMuchoBadgeManager private badgeManager = IMuchoBadgeManager(0xC439d29ee3C7fa237da928AD3A3D6aEcA9aA0717);
    function setBadgeManager(address _contract) external onlyAdmin { badgeManager = IMuchoBadgeManager(_contract); }


    /*--------------------------PARAMETERS--------------------------------------*/
    //Every time we update values and this period passed since last time, we save an APR for the period:
    uint256 public aprUpdatePeriod = 1 days;
    function setAprUpdatePeriod(uint256 _seconds) external onlyAdmin{ 
        aprUpdatePeriod = _seconds; 
    }

    //Fee (basic points) we will charge for swapping between mucho tokens:
    uint256 public bpSwapMuchoTokensFee = 25;
    function setSwapMuchoTokensFee(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 1000 && _percent >= 0, "not in range");
        bpSwapMuchoTokensFee = _percent;
    }

    //Special fee with discount for swapping, for NFT holders. Each plan can have its own fee, otherwise will use the default one for no-NFT holders.
    mapping(uint256 => MuchoBadgeSpecialFee) public bpSwapMuchoTokensFeeForBadgeHolders;
    function setSwapMuchoTokensFeeForPlan(uint256 _planId, uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 1000 && _percent >= 0, "not in range");
        require(_planId > 0, "not valid plan");
        bpSwapMuchoTokensFeeForBadgeHolders[_planId] = MuchoBadgeSpecialFee({fee : _percent, exists: true});
    }
    function removeSwapMuchoTokensFeeForPlan(uint256 _planId) external onlyTraderOrAdmin {
        require(_planId > 0, "not valid plan");
        bpSwapMuchoTokensFeeForBadgeHolders[_planId].exists = false;
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
            totalStaked:0,
            stakedFromDeposits:0,
            lastUpdate: block.timestamp, 
            stakable: false,
            depositFee: 0,
            withdrawFee: 0
        }));

        int256[30] memory apr;
        aprInfo.push(AprInfo({
            lastTotalStaked:0,
            lastStakedFromDeposits:0,
            lastAprUpdate: block.timestamp, 
            apr: apr
        }));

        return uint8(vaultInfo.length.sub(1));
    }

    //Sets a deposit fee for a vault:
    function setDepositFee(uint8 _vaultId, uint16 _fee) external onlyTraderOrAdmin validVault(_vaultId){
        require(_fee < 500, "MuchoVault: Max deposit fee exceeded");
        vaultInfo[_vaultId].depositFee = _fee;
    }

    //Sets a withdraw fee for a vault:
    function setWithdrawFee(uint8 _vaultId, uint16 _fee) external onlyTraderOrAdmin validVault(_vaultId){
        require(_fee < 100, "MuchoVault: Max withdraw fee exceeded");
        vaultInfo[_vaultId].withdrawFee = _fee;
    }

    //Opens or closes a vault for deposits:
    function setOpenVault(uint8 _vaultId, bool open) public onlyTraderOrAdmin validVault(_vaultId) {
        vaultInfo[_vaultId].stakable = open;
    }

    //Opens or closes ALL vaults for deposits:
    function setOpenAllVault(bool open) external onlyTraderOrAdmin {
        for (uint8 _vaultId = 0; _vaultId < vaultInfo.length; ++ _vaultId){
            setOpenVault(_vaultId, open);
        }
    }

    // Updates the totalStaked amount and refreshes apr (if it's time) in a vault:
    function updateVault(uint256 _vaultId) public onlyTraderOrAdmin validVault(_vaultId)  {
        uint256 diffTime = block.timestamp.sub(vaultInfo[_vaultId].lastUpdate);

        //Update total staked
        vaultInfo[_vaultId].lastUpdate = block.timestamp;
        vaultInfo[_vaultId].totalStaked = muchoHub.getTotalStaked(address(vaultInfo[_vaultId].depositToken));

        //If it's time, update apr
        if(diffTime >= aprUpdatePeriod){
            aprInfo[_vaultId].updateApr(vaultInfo[_vaultId].totalStaked, vaultInfo[_vaultId].stakedFromDeposits);
        }
    }

    // Updates all vaults:
    function updateAllVaults() public onlyTraderOrAdmin {
        for (uint8 _vaultId = 0; _vaultId < vaultInfo.length; ++ _vaultId){
            updateVault(_vaultId);
        }
    }

    // Refresh Investment and update all vaults:
    function refreshAndUpdateAllVaults() external onlyTraderOrAdmin {
        muchoHub.refreshAllInvestments();
        updateAllVaults();
    }

    /*----------------------------Swaps between muchoTokens handling------------------------------*/

    //Gets the number of tokens user will get from a mucho swap:
    function getSwap(uint8 _sourceVaultId, uint256 _amountSourceMToken, uint8 _destVaultId) external view
                     validVault(_sourceVaultId) validVault(_destVaultId) returns(uint256) {
        require(_amountSourceMToken > 0, "MuchoVaultV2.swapMuchoToken: Insufficent amount");

        uint256 ownerAmount = getSwapFee(msg.sender).mul(_amountSourceMToken).div(10000);
        uint256 destOutAmount = 
                    getDestinationAmountMuchoTokenExchange(_sourceVaultId, _destVaultId, _amountSourceMToken, ownerAmount);

        return destOutAmount;
    }

    //Performs a muchoTokens swap
    function swap(uint8 _sourceVaultId, uint256 _amountSourceMToken, uint8 _destVaultId, uint256 _amountOutExpected, uint16 _maxSlippage) external
                     validVault(_sourceVaultId) validVault(_destVaultId) nonReentrant {

        require(_amountSourceMToken > 0, "MuchoVaultV2.swapMuchoToken: Insufficent amount");
        require(_maxSlippage < 10000, "MuchoVaultV2.swapMuchoToken: Maxslippage is not valid");
        IMuchoToken sMToken = vaultInfo[_sourceVaultId].muchoToken;
        require(sMToken.balanceOf(msg.sender) >= _amountSourceMToken, "MuchoVaultV2.swapMuchoToken: Not enough balance");

        uint256 sourceOwnerAmount = getSwapFee(msg.sender).mul(_amountSourceMToken).div(10000);
        uint256 destOutAmount = 
                    getDestinationAmountMuchoTokenExchange(_sourceVaultId, _destVaultId, _amountSourceMToken, sourceOwnerAmount);

        require(destOutAmount > 0, "MuchoVaultV2.swapMuchoToken: user would get nothing");
        require(destOutAmount >= _amountOutExpected.mul(10000 - _maxSlippage).div(10000), "MuchoVaultV2.swapMuchoToken: Max slippage exceeded");

        IMuchoToken dMToken = vaultInfo[_destVaultId].muchoToken;

        //Send fee to protocol owner
        if(sourceOwnerAmount > 0)
            sMToken.mint(protocolOwner(), sourceOwnerAmount);
        
        //Send result to user
        if(destOutAmount > 0)
            dMToken.mint(msg.sender, destOutAmount);

        sMToken.burn(msg.sender, _amountSourceMToken);
        //console.log("    SOL - Burnt", _amountSourceMToken);
    }

    /*----------------------------CORE: User deposit and withdraw------------------------------*/
    
    //Deposits an amount in a vault
    function deposit(uint8 _vaultId, uint256 _amount) public validVault(_vaultId) nonReentrant {
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        IERC20 dToken = vaultInfo[_vaultId].depositToken;

        /*console.log(block.number , "SOL - DEPOSITING");
        console.log(block.number , "Sender and balance", msg.sender, dToken.balanceOf(msg.sender));
        console.log(block.number , "amount", _amount);*/
        
        require(_amount != 0, "MuchoVaultV2.deposit: Insufficent amount");
        require(msg.sender != address(0), "MuchoVaultV2.deposit: address is not valid");
        require(_amount <= dToken.balanceOf(msg.sender), "MuchoVaultV2.deposit: balance too low" );
        require(vaultInfo[_vaultId].stakable, "MuchoVaultV2.deposit: not stakable");
     
        // Gets the amount of deposit token locked in the contract
        uint256 totalStakedTokens = vaultInfo[_vaultId].totalStaked;

        // Gets the amount of muchoToken in existence
        uint256 totalShares = mToken.totalSupply();

        // Remove the deposit fee and calc amount after fee
        uint256 feeMultiplier = uint256(10000).sub(vaultInfo[_vaultId].depositFee);
        uint256 amountAfterFee = _amount.mul(feeMultiplier).div(10000);

        // If no muchoToken exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalStakedTokens == 0) {
            mToken.mint(msg.sender, amountAfterFee);
        } 
        // Calculate and mint the amount of muchoToken the depositToken is worth. The ratio will change overtime with APR
        else {
            uint256 what = amountAfterFee.mul(totalShares).div(totalStakedTokens);
            mToken.mint(msg.sender, what);
        }
        
        vaultInfo[_vaultId].totalStaked = vaultInfo[_vaultId].totalStaked.add(amountAfterFee);
        vaultInfo[_vaultId].stakedFromDeposits = vaultInfo[_vaultId].stakedFromDeposits.add(amountAfterFee);

        muchoHub.depositFrom(msg.sender, address(dToken), _amount);
    }

    //Withdraws from a vault. The user should have muschoTokens that will be burnt
    function withdraw(uint8 _vaultId, uint256 _share) public validVault(_vaultId) nonReentrant {

        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        IERC20 dToken = vaultInfo[_vaultId].depositToken;

        require(_share != 0, "MuchoVaultV2.withdraw: Insufficient amount");
        require(msg.sender != address(0), "MuchoVaultV2.withdraw: address is not valid");
        require(_share <= mToken.balanceOf(msg.sender), "MuchoVaultV2.withdraw: balance too low");

        // Calculates the amount of depositToken the muchoToken is worth
        uint256 amountOut = _share.mul(vaultInfo[_vaultId].totalStaked).div(mToken.totalSupply());

        vaultInfo[_vaultId].totalStaked = vaultInfo[_vaultId].totalStaked.sub(amountOut);
        vaultInfo[_vaultId].stakedFromDeposits = vaultInfo[_vaultId].stakedFromDeposits.sub(amountOut);
        mToken.burn(msg.sender, _share);

        // Applies withdraw fee:
        if(vaultInfo[_vaultId].withdrawFee > 0){
            uint256 feeMultiplier = uint256(10000).sub(vaultInfo[_vaultId].withdrawFee);
            amountOut = amountOut.mul(feeMultiplier).div(100000);
        }

        muchoHub.withdrawFrom(msg.sender, address(dToken), amountOut);
    }


    /*---------------------------------INFO VIEWS---------------------------------------*/

    //Displays total amount of staked tokens in a vault:
    function vaultTotalStaked(uint8 _vaultId) validVault(_vaultId) external view returns(uint256) {
        return vaultInfo[_vaultId].totalStaked;
    }

    //Displays total amount of staked tokens from deposits (excluding profit) in a vault:
    function vaultStakedFromDeposits(uint8 _vaultId) validVault(_vaultId) external view returns(uint256) {
        return vaultInfo[_vaultId].stakedFromDeposits;
    }

    //Displays total amount a user has staked in a vault:
    function investorVaultTotalStaked(uint8 _vaultId, address _address) validVault(_vaultId) external view returns(uint256) {
        require(_address != address(0), "MuchoVaultV2.displayStakedBalance: No valid address");
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        uint256 totalShares = mToken.totalSupply();
        uint256 amountOut = mToken.balanceOf(_address).mul(vaultInfo[_vaultId].totalStaked).div(totalShares);
        return amountOut;
    }

    //Price Muchotoken vs "real" token:
    function muchoTokenToDepositTokenPrice(uint8 _vaultId) validVault(_vaultId) external view returns(uint256) {
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        uint256 totalShares = mToken.totalSupply();
        uint256 amountOut = (vaultInfo[_vaultId].totalStaked).mul(10**18).div(totalShares);
        return amountOut;
    }

    //Total USD in a vault (18 decimals):
    function vaultTotalUSD(uint8 _vaultId) validVault(_vaultId) public view returns(uint256) {
         return getUSD(vaultInfo[_vaultId].depositToken, vaultInfo[_vaultId].totalStaked);
    }

    //Total USD an investor has in a vault:
    function investorVaultTotalUSD(uint8 _vaultId, address _user) validVault(_vaultId) public view returns(uint256) {
        require(_user != address(0), "MuchoVaultV2.totalUserVaultUSD: Invalid address");
        IMuchoToken mToken = vaultInfo[_vaultId].muchoToken;
        uint256 mTokenUser = mToken.balanceOf(_user);
        uint256 mTokenTotal = mToken.totalSupply();

        if(mTokenUser == 0 || mTokenTotal == 0)
            return 0;

        return getUSD(vaultInfo[_vaultId].depositToken, vaultInfo[_vaultId].totalStaked.mul(mTokenUser).div(mTokenTotal));
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
    
    //Gets vault's last periods aprs:
    function getLastPeriodsApr(uint8 _vaultId) external view validVault(_vaultId) returns(int256[30] memory){
        return aprInfo[_vaultId].apr;
    }
    

    /*-----------------------------------SWAP MUCHOTOKENS--------------------------------------*/

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
    function getDestinationAmountMuchoTokenExchange(uint8 _sourceVaultId, 
                                            uint8 _destVaultId,
                                            uint256 _amountSourceMToken,
                                            uint256 _ownerFeeAmount) 
                                                    internal view returns(uint256){
        require(_amountSourceMToken > 0, "Insufficent amount");

        uint256 sourcePrice = priceFeed.getPrice(address(vaultInfo[_sourceVaultId].depositToken)).div(10**12);
        uint256 destPrice = priceFeed.getPrice(address(vaultInfo[_destVaultId].depositToken)).div(10**12);
        uint256 decimalsDest = vaultInfo[_destVaultId].depositToken.decimals();
        uint256 decimalsSource = vaultInfo[_sourceVaultId].depositToken.decimals();

        //Subtract owner fee
        if(_ownerFeeAmount > 0){
            _amountSourceMToken = _amountSourceMToken.sub(_ownerFeeAmount);
        }
        //uint256 amountSourceForOwner = getOwnerFeeMuchoTokenExchange(_sourceVaultId, _destVaultId, _amountSourceMToken);
        /*{
            //Calc swap fee
            uint256 swapFee = getSwapFee(msg.sender);

            //Mint swap fee tokens to owner:
            if(swapFee > 0){
                amountSourceForOwner = _amountSourceMToken.mul(swapFee).div(10000);
                _amountSourceMToken = _amountSourceMToken.sub(amountSourceForOwner);
            }
        }*/

        uint256 amountTargetForUser = 0;
        {
            /*console.log("    SOL - _amountSourceMToken|", _amountSourceMToken);
            console.log("    SOL - sourceTotalStk|", vaultInfo[_sourceVaultId].totalStaked);
            console.log("    SOL - sourcePrice|", sourcePrice);
            console.log("    SOL - mDestTotalSupply|", vaultInfo[_destVaultId].muchoToken.totalSupply());*/

            amountTargetForUser = _amountSourceMToken
                                        .mul(vaultInfo[_sourceVaultId].totalStaked)
                                        .mul(sourcePrice)
                                        .mul(vaultInfo[_destVaultId].muchoToken.totalSupply());
        }
        //decimals handling
        if(decimalsDest > decimalsSource){
            //console.log("    SOL - DecimalsBiggerDif|", decimalsDest - decimalsSource);
            amountTargetForUser = amountTargetForUser.mul(10**(decimalsDest - decimalsSource));
        }
        else if(decimalsDest < decimalsSource){
            //console.log("    SOL - DecimalsSmallerDif|", decimalsSource - decimalsDest);
            amountTargetForUser = amountTargetForUser.div(10**(decimalsSource - decimalsDest));
        }

        amountTargetForUser = amountTargetForUser.div(vaultInfo[_sourceVaultId].muchoToken.totalSupply())
                                    .div(vaultInfo[_destVaultId].totalStaked)
                                    .div(destPrice);
                                    
        /*console.log("    SOL - amountTarget1|", amountTargetForUser);
        console.log("    SOL - sourceMSupply|", vaultInfo[_sourceVaultId].muchoToken.totalSupply());
        console.log("    SOL - destTotalStk|", vaultInfo[_destVaultId].totalStaked);
        console.log("    SOL - destPrice|", destPrice);*/
        
        return /*(amountSourceForOwner, */amountTargetForUser/*)*/;
    }
}