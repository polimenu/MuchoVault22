// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../../interfaces/IMuchoProtocol.sol";
import "../../interfaces/IPriceFeed.sol";
import "../../interfaces/IMuchoRewardRouter.sol";
import "../../interfaces/GMX/IGLPRouter.sol";
import "../../interfaces/GMX/IRewardRouter.sol";
import "../../interfaces/GMX/IGLPPriceFeed.sol";
import "../../interfaces/GMX/IGLPVault.sol";
import "../MuchoRoles.sol";
import "../../lib/AprInfo.sol";
//import "./IMuchoGMXController.sol";
//import "../../lib/UintSafe.sol";

contract MuchoProtocolNoInvestment is IMuchoProtocol, MuchoRoles, ReentrancyGuard{

    using SafeMath for uint256;
    using SafeMath for uint64;
    using SafeERC20 for IERC20;
    using AprLib for AprInfo;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet tokenList;
    mapping(address => uint256) tokenAmount;
    mapping(address => uint256) tokenAmountFromDeposits;
    mapping(address => EnumerableSet.AddressSet) tokenToSecondaryTokens;
    uint256 lastWeightUpdate;

    uint256 public lastUpdate;

    uint256 public aprUpdatePeriod = 1 days;
    function setAprUpdatePeriod(uint256 _seconds) external onlyAdmin{ aprUpdatePeriod = _seconds; }

    uint256 slippage = 100;
    function setSlippage(uint256 _slippage) external onlyOwner{
        require(_slippage >= 200 && _slippage <= 1000, "not in range"); slippage = _slippage;
    }

    //Claim esGmx, set false to save gas
    bool public claimEsGmx = false;
    function updateClaimEsGMX(bool _new) external onlyOwner { claimEsGmx = _new; }

    //GMX tokens - escrowed GMX and staked GLP
    IERC20 public EsGMX = IERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);
    function updateEsGMX(address _new) external onlyOwner { EsGMX = IERC20(_new); }
    IERC20 public fsGLP = IERC20 (0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    function updatefsGLP(address _new) external onlyOwner { fsGLP = IERC20(_new); }
    IERC20 public WETH = IERC20 (0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    function updateWETH(address _new) external onlyOwner { WETH = IERC20(_new); }

    //Interfaces to interact with GMX protocol

    //GLP Router:
    IGLPRouter public glpRouter = IGLPRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5); 
    function updateRouter(address _newRouter) external onlyAdmin { glpRouter = IGLPRouter(_newRouter); }

    //GLP Reward Router:
    IRewardRouter public glpRewardRouter = IRewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    function updateRewardRouter(address _newRouter) external onlyAdmin { glpRewardRouter = IRewardRouter(_newRouter); } 

    //GLP Staking Pool address:
    address poolGLP = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    function updatepoolGLP(address _newManager) external onlyAdmin { poolGLP = _newManager; } 

    //GLP Vault
    IGLPVault public glpVault = IGLPVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    function updateGLPVault(address _newVault) external onlyAdmin { glpVault = IGLPVault(_newVault); } 

    //MuchoRewardRouter Interaction for NFT Holders
    IMuchoRewardRouter muchoRewardRouter = IMuchoRewardRouter(0x0000000000000000000000000000000000000000);
    function updateMuchoRewardRouter(address _newRouter) external onlyOwner { muchoRewardRouter = IMuchoRewardRouter(_newRouter); }

    //IMuchoGMXController controller has the logic of the investment we need to make/unmake in GLP:
    //IMuchoGMXController muchoInvestmentController = IMuchoGMXController(0x0000000000000000000000000000000000000000);
    //function updateMuchoGMXController(address _new) external onlyOwner { muchoInvestmentController = IMuchoGMXController(_new); }

    RewardSplit rewardSplit;
    IMuchoProtocol compoundProtocol;
    mapping(address => AprInfo) tokenAprInfo;
   
    // Safety not-invested margin min and desired (2 decimals)
    uint256 public minNotInvestedPercentage = 250;
    function setMinNotInvestedPercentage(uint256 _percent) external onlyAdmin {
        require(_percent < 9000 && _percent >= 0, "MuchoProtocolGMX: minNotInvestedPercentage not in range");
        minNotInvestedPercentage = _percent;
    }
    uint256 public desiredNotInvestedPercentage = 500;
    function setDesiredNotInvestedPercentage(uint256 _percent) external onlyAdmin {
        require(_percent < 9000 && _percent >= 0, "MuchoProtocolGMX: desiredNotInvestedPercentage not in range");
        desiredNotInvestedPercentage = _percent;
    }

    //If variation against desired weight is less than this, do not move:
    uint256 public minBasisPointsMove = 100; 
    function setMinWeightBasisPointsMove(uint256 _percent) external onlyAdmin {
        require(_percent < 500 && _percent > 0, "MuchoProtocolGMX: minBasisPointsMove not in range");
        minBasisPointsMove = _percent;
    }

    IGLPPriceFeed priceFeed;
    function setPriceFeed(IGLPPriceFeed _feed) onlyAdmin external{
        priceFeed = _feed;
    }

    function addSecondaryToken(address _mainToken, address _secondary) onlyAdmin external{
        tokenToSecondaryTokens[_mainToken].add(_secondary);
    }
    function removeSecondaryToken(address _mainToken, address _secondary) onlyAdmin external{
        tokenToSecondaryTokens[_mainToken].remove(_secondary);
    }

    //Manual mode for desired weights (in automatic, gets it from GLP Contract):
    bool public manualModeWeights = false;
    function setManualModeWeights(bool _manual) external onlyOwner { manualModeWeights = _manual; }
    mapping(address => uint256) glpWeight;
    mapping(address => uint256) glpUsdgs;
    function updateGlpWeights() onlyTraderOrAdmin public{
        require(!manualModeWeights, "MuchoProtocolGmx: manual mode");

        // Store all USDG value (deposit + secondary tokens) for each vault, and total USDG amount to divide later
        uint256 totalUsdg = getTotalAndUpdateVaultsUsdg();

        // Calculate weights for every vault
        uint256 totalWeight = 0;
        for(uint i = 0; i < tokenList.length(); i = i.add(1)){
            address token = tokenList.at(i);
            uint256 vaultWeight = glpUsdgs[token].mul(10000).div(totalUsdg);
            glpWeight[token] = vaultWeight;
            totalWeight = totalWeight.add(vaultWeight);
        }

        // Check total weight makes sense
        uint256 diff = (totalWeight > 10000) ? (totalWeight - 10000) : (10000 - totalWeight);
        require(diff < 100, "MuchoVaultV2.updateDesiredWeightsFromGLP: Total weight far away from 1");

        //Update date
        lastWeightUpdate = block.timestamp;
    }

    //Gets the total USDG in GLP and the USDG in GLP for each of our vaults' tokens:
    function getTotalAndUpdateVaultsUsdg() internal returns(uint256){
        uint256 totalUsdg;
        for(uint i = 0; i < tokenList.length(); i = i.add(1)){
            address token = tokenList.at(i);
            uint256 vaultUsdg = glpVault.usdgAmounts(token);
            
            for(uint j = 0; j < tokenToSecondaryTokens[token].length(); j = j.add(1)){
                vaultUsdg = vaultUsdg.add(glpVault.usdgAmounts(tokenToSecondaryTokens[token].at(j)));
            }

            glpUsdgs[token] = vaultUsdg;
            totalUsdg = totalUsdg.add(vaultUsdg);
        }

        return totalUsdg;
    }

    //Sets manually the desired weight for a vault
    function setWeight(address _token, uint256 _percent) external onlyOwner {
        require(_percent < 7000 && _percent > 0, "MuchoInvestmentController.setWeight: not in range");
        require(manualModeWeights, "MuchoInvestmentController.setWeight: automatic mode");
        glpWeight[_token] = _percent;
    }

    function getMinTokenByWeight(uint256 _totalUsd, uint256[] memory _tokenUsd) internal view returns(address, uint256){
        uint maxDiff = 0;
        uint256 minUsd;
        address minToken;

        for(uint i = 0; i < tokenList.length(); i = i.add(1)){
            address token = tokenList.at(i);
            if(glpWeight[token] > _tokenUsd[i].mul(10000).div(_totalUsd)){
                uint diff = glpWeight[token].sub(_tokenUsd[i].mul(10000).div(_totalUsd));
                if(diff > maxDiff){
                    minToken = token;
                    minUsd = _tokenUsd[i];
                    maxDiff = diff;
                }
            }
        }

        return (minToken, minUsd);
    }


    function refreshInvestment() onlyTraderOrAdmin external {
        

        if(!manualModeWeights)
            updateGlpWeights();
        (uint256 totalUsd, uint256[] memory tokenUsd) = getTotalUSDWithTokensUsd();
        (address minTokenByWeight, uint256 minTokenUsd) = getMinTokenByWeight(totalUsd, tokenUsd);

        //Calculate and do move for the minimum weight token
        doMinTokenWeightMove(minTokenByWeight, minTokenUsd);

        //Calc new total USD
        minTokenUsd = getTokenTotalUSD(minTokenByWeight);
        totalUsd = minTokenUsd.mul(10000).div(glpWeight[minTokenByWeight]);
 
        //Calculate move for every token different from the main one:
        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            address token = tokenList.at(i);

            if(token != minTokenByWeight){

                doNotMinTokenMove(token, glpWeight[token], tokenUsd[i], totalUsd);
            }
        }

        lastUpdate = block.timestamp;
        updateAprs();
    }

    function updateAprs() internal {
        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            address token = tokenList.at(i);
            uint256 timeDiff = block.timestamp.sub(tokenAprInfo[token].lastAprUpdate);

            //If it's time, update apr
            if(timeDiff >= aprUpdatePeriod){
                    tokenAprInfo[token].updateApr(tokenAmount[token], tokenAmountFromDeposits[token]);
            }
        }
    }


    function doMinTokenWeightMove(address _minTokenByWeight, uint256 _minTokenUsd) internal {
        uint256 notInvestedBalance = IERC20(_minTokenByWeight).balanceOf(address(this));
        uint256 notInvestedBP = notInvestedBalance.mul(10000).div(_minTokenUsd);

        //Invested less than desired:
        if(notInvestedBP > desiredNotInvestedPercentage && notInvestedBP.sub(desiredNotInvestedPercentage) > minBasisPointsMove){ 
            uint256 amountToMove = notInvestedBalance.sub(desiredNotInvestedPercentage.mul(_minTokenUsd).div(10000));
            swaptoGLP(amountToMove, _minTokenByWeight);
        }

        //Invested more than desired:
        else if(notInvestedBP < minNotInvestedPercentage){
            uint256 amountToMove = desiredNotInvestedPercentage.mul(_minTokenUsd).div(10000).sub(notInvestedBalance);
            swapGLPto(amountToMove, _minTokenByWeight, 0);
        }

    }

    function doNotMinTokenMove(address _token,
                                uint256 _desiredWeight, 
                                uint256 _totalTokenUSD,
                                uint256 _newTotalInvested) 
                                    internal {
        uint256 price = priceFeed.getPrice(_token);
        uint256 newUSDInvested = _desiredWeight.mul(_newTotalInvested).div(10000);
        uint256 currentUSDInvested = _totalTokenUSD.sub(getTotalNotInvested(_token).div(price));

        //Invested less than desired:
        if(newUSDInvested > currentUSDInvested && newUSDInvested.sub(currentUSDInvested).mul(10000).div(_totalTokenUSD) > minBasisPointsMove){
            swaptoGLP(newUSDInvested.sub(currentUSDInvested).div(priceFeed.getPrice(_token)), _token);
        }

        //Invested more than desired:
        else if(newUSDInvested < currentUSDInvested && currentUSDInvested.sub(newUSDInvested).mul(10000).div(currentUSDInvested) > minBasisPointsMove){
            swapGLPto(currentUSDInvested.sub(newUSDInvested).div(priceFeed.getPrice(_token)), _token, 0);
        }
    }

    function cycleRewards() onlyTraderOrAdmin external{
        if(claimEsGmx){
            glpRewardRouter.claimEsGmx();
            uint256 balanceEsGmx = EsGMX.balanceOf(address(this));
            if(balanceEsGmx > 0)
                glpRewardRouter.stakeEsGmx(balanceEsGmx);
        }
        cycleRewardsETH();
    }

    //Get ETH rewards and distribute among the vaults and owner
    function cycleRewardsETH() private {

        //claim weth fees
        glpRewardRouter.claimFees();
        uint256 rewards = WETH.balanceOf(address(this));

        //use compoundPercentage to calculate the total amount and swap to GLP
        uint256 compoundAmount = rewards.mul(uint256(10000).sub(rewardSplit.NftPercentage).sub(rewardSplit.ownerPercentage)).div(10000);
        if(compoundProtocol == this){ //autocompound
            autoCompoundWETH(compoundAmount);
        }
        else{
            notInvestedTrySend(address(WETH), compoundAmount, address(compoundProtocol));
        }

        //use stakersPercentage to calculate the amount for rewarding stakers
        uint256 stakersAmount = rewards.mul(rewardSplit.NftPercentage).div(10000);
        muchoRewardRouter.depositRewards(address(WETH), stakersAmount);

        //send the rest to owner
        WETH.transfer(owner(),  WETH.balanceOf(address(this)));
    }

    function autoCompoundWETH(uint256 _amount) private{
        uint256 previousGlp = fsGLP.balanceOf(address(this));
        swaptoGLP(_amount, address(WETH));
        uint256 increasePercentage = fsGLP.balanceOf(address(this)).div(previousGlp);
        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            tokenAmount[tokenList.at(i)] = tokenAmount[tokenList.at(i)].mul(increasePercentage);
        }
    }

    function withdrawAndSend(address _token, uint256 _amount, address _target) onlyOwner nonReentrant external{
        uint256 usdAmount = _amount.mul(priceFeed.getPrice(_token));
        uint256 glpOut = usdAmount.mul(uint256(10000).add(slippage)).div(10000).div(priceFeed.getGLPprice());
        swapGLPto(glpOut, _token, _amount);
        IERC20(_token).safeTransfer(_target, _amount);
    }
    function notInvestedTrySend(address _token, uint256 _amount, address _target) onlyOwner nonReentrant public returns(uint256){
        IERC20 tk = IERC20(_token);
        uint256 balance = tk.balanceOf(address(this));
        uint256 amountToTransfer = _amount;
        if(balance < _amount)
            amountToTransfer = balance;

        tokenAmount[_token] = tokenAmount[_token].sub(amountToTransfer);
        tokenAmountFromDeposits[_token] = tokenAmountFromDeposits[_token].sub(amountToTransfer);
        tk.safeTransfer(_target, amountToTransfer);
        return amountToTransfer;
    }
    function notifyDeposit(address _token, uint256 _amount) onlyOwner nonReentrant external{
        tokenList.add(_token);
        tokenAmount[_token] = tokenAmount[_token].add(_amount);
        tokenAmountFromDeposits[_token] = tokenAmountFromDeposits[_token].add(_amount);
    }

    function setRewardPercentages(RewardSplit calldata _split) onlyTraderOrAdmin external{
        require(_split.NftPercentage.add(_split.ownerPercentage) <= 10000, "NTF and owner fee are more than 100%");
        rewardSplit = RewardSplit({NftPercentage: _split.NftPercentage, ownerPercentage: _split.ownerPercentage});
    }

    function setCompoundProtocol(IMuchoProtocol _target) onlyTraderOrAdmin external{
        compoundProtocol = _target;
    }
    function setMuchoRewardRouter(address _contract) onlyAdmin external{
        muchoRewardRouter = IMuchoRewardRouter(_contract);
    }

    function getLastPeriodsApr(address _token) external view returns(int256[30] memory){
        return tokenAprInfo[_token].apr;
    }
    function getTotalNotInvested(address _token) public view returns(uint256){
        return IERC20(_token).balanceOf(address(this));
    }
    function getTotalStaked(address _token) external view returns(uint256){
        return tokenAmount[_token];
    }

    function getTotalUSD() public view returns(uint256){
        (uint256 totalUsd,) = getTotalUSDWithTokensUsd();
        return totalUsd;
    }
    function getTotalUSDWithTokensUsd() public view returns(uint256, uint256[] memory){
        uint256 totalUsd = 0;
        uint256[] memory tokenUsds = new uint256[](tokenList.length());
        uint256 totalGlpUsd = fsGLP.balanceOf(address(this)).mul(priceFeed.getGLPprice());

        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            address token = tokenList.at(i);
            //Add not invested balance
            uint256 tokenUsd = IERC20(token).balanceOf(address(this)).mul(priceFeed.getPrice(token));
            //Add glp part
            tokenUsd = tokenUsd.add(totalGlpUsd.mul(glpWeight[token]).div(10000));
            totalUsd = totalUsd.add(tokenUsd);
            tokenUsds[i] = tokenUsd;
        }

        return (totalUsd, tokenUsds);
    }
    function getTokenTotalUSD(address _token) public  view returns(uint256){
        uint256 totalGlpUsd = fsGLP.balanceOf(address(this)).mul(priceFeed.getGLPprice());
        //Add not invested balance
        uint256 tokenUsd = IERC20(_token).balanceOf(address(this)).mul(priceFeed.getPrice(_token));
        //Add glp part
        tokenUsd = tokenUsd.add(totalGlpUsd.mul(glpWeight[_token]).div(10000));

        return tokenUsd;
    }

    /*----------------------------GLP mint and token conversion------------------------------*/

    function swapGLPto(uint256 _amount, address token, uint256 min_receive) private returns(uint256) {
        return glpRouter.unstakeAndRedeemGlp(token, _amount, min_receive, address(this));
    }

    //Mint GLP from token
    function swaptoGLP(uint256 _amount, address token) private returns(uint256) {
        IERC20(token).safeApprove(poolGLP, _amount);
        return glpRouter.mintAndStakeGlp(token, _amount,0, 0);
    }


}