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
import "hardhat/console.sol";

contract MuchoProtocolGMX is IMuchoProtocol, MuchoRoles, ReentrancyGuard{

    using SafeMath for uint256;
    using SafeMath for uint64;
    using SafeERC20 for IERC20;
    using AprLib for AprInfo;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet tokenList;
    mapping(address => uint256) tokenAmountFromDeposits;
    mapping(address => EnumerableSet.AddressSet) tokenToSecondaryTokens;
    uint256 lastWeightUpdate;

    uint256 public lastUpdate;

    function protocolName() public pure returns(string memory){
        return "MuchoProtocolGMX";
    }
    function protocolDescription() public pure returns(string memory){
        return "Performs a delta neutral strategy against GLP yield from GMX protocol";
    }

    uint256 public aprUpdatePeriod = 1 days;
    function setAprUpdatePeriod(uint256 _seconds) external onlyTraderOrAdmin{ aprUpdatePeriod = _seconds; }

    uint256 public slippage = 100;
    function setSlippage(uint256 _slippage) external onlyTraderOrAdmin{
        require(_slippage >= 10 && _slippage <= 1000, "not in range"); slippage = _slippage;
    }

    //Claim esGmx, set false to save gas
    bool public claimEsGmx = false;
    function updateClaimEsGMX(bool _new) external onlyTraderOrAdmin { claimEsGmx = _new; }

    //GMX tokens - escrowed GMX and staked GLP
    IERC20 public EsGMX = IERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);
    function updateEsGMX(address _new) external onlyAdmin { EsGMX = IERC20(_new); }
    IERC20 public fsGLP = IERC20 (0x1aDDD80E6039594eE970E5872D247bf0414C8903);
    function updatefsGLP(address _new) external onlyAdmin { fsGLP = IERC20(_new); }
    IERC20 public WETH = IERC20 (0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    function updateWETH(address _new) external onlyAdmin { WETH = IERC20(_new); }

    //Interfaces to interact with GMX protocol

    //GLP Router:
    IGLPRouter public glpRouter = IGLPRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5); 
    function updateRouter(address _newRouter) external onlyAdmin { glpRouter = IGLPRouter(_newRouter); }

    //GLP Reward Router:
    IRewardRouter public glpRewardRouter = IRewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
    function updateRewardRouter(address _newRouter) external onlyAdmin { glpRewardRouter = IRewardRouter(_newRouter); } 

    //GLP Staking Pool address:
    address public poolGLP = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    function updatepoolGLP(address _newManager) external onlyAdmin { poolGLP = _newManager; } 

    //GLP Vault
    IGLPVault public glpVault = IGLPVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    function updateGLPVault(address _newVault) external onlyAdmin { glpVault = IGLPVault(_newVault); } 

    //MuchoRewardRouter Interaction for NFT Holders
    IMuchoRewardRouter public muchoRewardRouter = IMuchoRewardRouter(0x0000000000000000000000000000000000000000);
    function setMuchoRewardRouter(address _contract) onlyAdmin external{ muchoRewardRouter = IMuchoRewardRouter(_contract);}

    RewardSplit public rewardSplit;
    IMuchoProtocol public compoundProtocol;
    mapping(address => AprInfo) tokenAprInfo;
   
    // Safety not-invested margin min and desired (2 decimals)
    uint256 public minNotInvestedPercentage = 250;
    function setMinNotInvestedPercentage(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 9000 && _percent >= 0, "MuchoProtocolGMX: minNotInvestedPercentage not in range");
        minNotInvestedPercentage = _percent;
    }
    uint256 public desiredNotInvestedPercentage = 500;
    function setDesiredNotInvestedPercentage(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 9000 && _percent >= 0, "MuchoProtocolGMX: desiredNotInvestedPercentage not in range");
        desiredNotInvestedPercentage = _percent;
    }

    //If variation against desired weight is less than this, do not move:
    uint256 public minBasisPointsMove = 100; 
    function setMinWeightBasisPointsMove(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 500 && _percent > 0, "MuchoProtocolGMX: minBasisPointsMove not in range");
        minBasisPointsMove = _percent;
    }

    //Lapse to refresh weights when refreshing investment
    uint256 public maxRefreshWeightLapse = 1 days;
    function setMaxRefreshWeightLapse(uint256 _mw) onlyTraderOrAdmin external{
        require(_mw > 0, "MuchoProtocolGmx: Not valid lapse");
        maxRefreshWeightLapse = _mw;
    }

    IGLPPriceFeed public priceFeed;
    function setPriceFeed(IGLPPriceFeed _feed) onlyAdmin external{
        priceFeed = _feed;
    }

    function addToken(address _token) onlyAdmin external{
        tokenList.add(_token);
    }

    function addSecondaryToken(address _mainToken, address _secondary) onlyAdmin external{
        tokenToSecondaryTokens[_mainToken].add(_secondary);
    }
    function removeSecondaryToken(address _mainToken, address _secondary) onlyAdmin external{
        tokenToSecondaryTokens[_mainToken].remove(_secondary);
    }

    //Manual mode for desired weights (in automatic, gets it from GLP Contract):
    bool public manualModeWeights = false;
    function setManualModeWeights(bool _manual) external onlyTraderOrAdmin { manualModeWeights = _manual; }
    mapping(address => uint256) glpWeight;
    mapping(address => uint256) glpUsdgs;

    //Updates desired weights from GLP in automatic mode:
    function updateGlpWeights() onlyTraderOrAdmin public{
        console.log("    SOL ***updateGlpWeights function***");
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
        require(diff < 100, "MuchoProtocolGmx.updateDesiredWeightsFromGLP: Total weight far away from 1");

        //Update date
        lastWeightUpdate = block.timestamp;
    }

    //Gets the total USDG in GLP and the USDG in GLP for each of our vaults' tokens:
    function getTotalAndUpdateVaultsUsdg() internal returns(uint256){
        //console.log("   SOL - getTotalAndUpdateVaultsUsdg");
        uint256 totalUsdg;
        for(uint i = 0; i < tokenList.length(); i = i.add(1)){
            //console.log("   SOL - token", i);

            address token = tokenList.at(i);
            uint256 vaultUsdg = glpVault.usdgAmounts(token);
            //console.log("   SOL - token usdg", vaultUsdg);
            
            for(uint j = 0; j < tokenToSecondaryTokens[token].length(); j = j.add(1)){
                uint256 secUsdg = glpVault.usdgAmounts(tokenToSecondaryTokens[token].at(j));
                //console.log("   SOL - SECONDARY token", j);
                //console.log("   SOL - SECONDARY token usdg", secUsdg);
                vaultUsdg = vaultUsdg.add(secUsdg);
            }

            glpUsdgs[token] = vaultUsdg;
            totalUsdg = totalUsdg.add(vaultUsdg);
        }

        return totalUsdg;
    }

    //Sets manually the desired weight for a vault
    function setWeight(address _token, uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 7000 && _percent > 0, "MuchoProtocolGmx.setWeight: not in range");
        require(manualModeWeights, "MuchoProtocolGmx.setWeight: automatic mode");
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

//ToDo: trader, admin or owner!

    //Updates weights, token investment, refreshes amounts and updates aprs:
    function refreshInvestment() onlyOwnerTraderOrAdmin external {
        console.log("    SOL ***refreshInvestment function***");
        if(!manualModeWeights && block.timestamp.sub(lastWeightUpdate) > maxRefreshWeightLapse){
            updateGlpWeights();
        }

        updateTokensInvestment();
        updateAprs();
    }


    function updateTokensInvestment() internal{
        console.log("    SOL ***updateTokensInvested function***");
        (uint256 totalUsd, uint256[] memory tokenUsd, uint256[] memory tokenInvestedUsd) = getTotalUSDWithTokensUsd();
        console.log("    SOL - totalUSD", totalUsd);
        console.log("    SOL - tokenUSD0", tokenUsd[0]);
        console.log("    SOL - tokenUSD1", tokenUsd[1]);
        console.log("    SOL - tokenUSD2", tokenUsd[2]);
        (address minTokenByWeight, uint256 minTokenUsd) = getMinTokenByWeight(totalUsd, tokenUsd);
        console.log("    SOL - minToken and USD", minTokenByWeight, minTokenUsd);

        //Calculate and do move for the minimum weight token
        doMinTokenWeightMove(minTokenByWeight);

        //Calc new total USD
        uint256 newTotalInvestedUsd = minTokenUsd.mul(10000 - desiredNotInvestedPercentage).div(glpWeight[minTokenByWeight]);
        console.log("    SOL - minTokenInvestedUsd - investedMin + weight", getTokenUSDInvested(minTokenByWeight), glpWeight[minTokenByWeight]);
        console.log("    SOL - totalInvestedUsd", newTotalInvestedUsd);
 
        //Calculate move for every token different from the main one:
        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            address token = tokenList.at(i);

            if(token != minTokenByWeight){
                doNotMinTokenMove(token, glpWeight[token], tokenUsd[i], tokenInvestedUsd[i], newTotalInvestedUsd);
            }
        }

        lastUpdate = block.timestamp;
        console.log("    SOL ***END updateTokensInvested function***");
    }

    function updateAprs() internal {
        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            address token = tokenList.at(i);
            uint256 timeDiff = block.timestamp.sub(tokenAprInfo[token].lastAprUpdate);

            //If it's time, update apr
            if(timeDiff >= aprUpdatePeriod){
                    tokenAprInfo[token].updateApr(getTokenStaked(token), tokenAmountFromDeposits[token]);
            }
        }
    }


    function doMinTokenWeightMove(address _minTokenByWeight) internal {
        console.log("    SOL ***doMinTokenWeightMove function***");
        uint256 totalBalance = getTokenStaked(_minTokenByWeight);
        uint256 notInvestedBalance = getTokenNotInvested(_minTokenByWeight);
        uint256 notInvestedBP = notInvestedBalance.mul(10000).div(totalBalance);
        console.log("    SOL - Not invested balance and BP and desiredBP", notInvestedBalance, notInvestedBP, desiredNotInvestedPercentage);

        //Invested less than desired:
        if(notInvestedBP > desiredNotInvestedPercentage && notInvestedBP.sub(desiredNotInvestedPercentage) > minBasisPointsMove){ 
            uint256 amountToMove = notInvestedBalance.sub(desiredNotInvestedPercentage.mul(totalBalance).div(10000));

            console.log("    SOL - Swap token to GLP", _minTokenByWeight, amountToMove);
            swaptoGLP(amountToMove, _minTokenByWeight);
        }

        //Invested more than desired:
        else if(notInvestedBP < minNotInvestedPercentage){
            uint256 amountToMove = desiredNotInvestedPercentage.mul(totalBalance).div(10000).sub(notInvestedBalance);
            console.log("    SOL - Will swap GLP to (amount token)", amountToMove, _minTokenByWeight);
            swapGLPto(amountToMove, _minTokenByWeight, 0);
        }


        console.log("    SOL ***END doMinTokenWeightMove function***");
    }

    //ToDo DEBUG - not working
    function doNotMinTokenMove(address _token,
                                uint256 _desiredWeight, 
                                uint256 _totalTokenUSD,
                                uint256 _currentUSDInvested,
                                uint256 _newTotalInvested) 
                                    internal {
        console.log("    SOL ***doNotMinTokenMove function*** (token, desiredWeight)", _token, _desiredWeight);
        console.log("    SOL    ***doNotMinTokenMove function*** (currentUSDInvested, totalUSD, newTotalUSD)", _currentUSDInvested.div(10**16), _totalTokenUSD.div(10**16), _newTotalInvested.div(10**16));
        uint256 newUSDInvested = _newTotalInvested.mul(_desiredWeight).div(10000);
        uint256 decimals = IERC20Metadata(_token).decimals();

        console.log("    SOL - doNotMinTokenMove - newUSDInvested:", newUSDInvested);

        //Invested less than desired:
        uint256 amountToMove;
        if(newUSDInvested > _currentUSDInvested && 
                newUSDInvested.sub(_currentUSDInvested).mul(10000).div(_totalTokenUSD) > minBasisPointsMove){
            uint256 amountUSDToMove = newUSDInvested.sub(_currentUSDInvested);
            amountToMove = amountUSDToMove.mul(10**(30+decimals-18)).div(priceFeed.getPrice(_token));
            console.log("    SOL - Investing more (amountUSD, amountToken)", amountUSDToMove.div(10**16), amountToMove.div(10**(decimals-6)));
            swaptoGLP(amountToMove, _token);
        }

        //Invested more than desired:
        else if(newUSDInvested < _currentUSDInvested && _currentUSDInvested.sub(newUSDInvested).mul(10000).div(_currentUSDInvested) > minBasisPointsMove){
            uint256 amountUSDToMove = _currentUSDInvested.sub(newUSDInvested);
            amountToMove = amountUSDToMove.mul(10**(30+decimals-18)).div(priceFeed.getPrice(_token));
            console.log("    SOL - Investing less (amountUSD, amountToken)", amountUSDToMove.div(10**16), amountToMove.div(10**(decimals-6)));
            swapGLPto(amountToMove, _token, 0);
        }

        console.log("    SOL ***END doNotMinTokenMove function***");
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
            swaptoGLP(compoundAmount, address(WETH));
        }
        else{
            notInvestedTrySend(address(WETH), compoundAmount, address(compoundProtocol));
        }

        //use stakersPercentage to calculate the amount for rewarding stakers
        uint256 stakersAmount = rewards.mul(rewardSplit.NftPercentage).div(10000);
        muchoRewardRouter.depositRewards(address(WETH), stakersAmount);

        //send the rest to owner
        WETH.safeTransfer(owner(),  WETH.balanceOf(address(this)));
    }

    function withdrawAndSend(address _token, uint256 _amount, address _target) onlyOwner nonReentrant external{
        console.log("    SOL ***withdrawAndSend***");
        uint8 tkDecimals = IERC20Metadata(_token).decimals();
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();
        console.log("    SOL - tkdecimals, glpDecimals", tkDecimals, glpDecimals);
        uint256 usdAmount = _amount.mul(priceFeed.getPrice(_token)).div(10**(30-18+tkDecimals));
        console.log("    SOL - _amount, usdAmount", _amount, usdAmount);
        console.log("    SOL - slippage", slippage);
        console.log("    SOL - glpPrice", priceFeed.getGLPprice().div(10**26));
        uint256 glpOut = usdAmount.mul(uint256(10000).add(slippage)).div(10000).mul(10**(30+glpDecimals-18)).div(priceFeed.getGLPprice());
        console.log("    SOL - glpOut", glpOut);
        swapGLPto(glpOut, _token, _amount);
        IERC20(_token).safeTransfer(_target, _amount);
        console.log("    SOL ***END withdrawAndSend***");
    }

    function notInvestedTrySend(address _token, uint256 _amount, address _target) onlyOwner nonReentrant public returns(uint256){
        IERC20 tk = IERC20(_token);
        uint256 balance = tk.balanceOf(address(this));
        uint256 amountToTransfer = _amount;
        if(balance < _amount)
            amountToTransfer = balance;

        tokenAmountFromDeposits[_token] = tokenAmountFromDeposits[_token].sub(amountToTransfer);
        tk.safeTransfer(_target, amountToTransfer);
        return amountToTransfer;
    }
    function notifyDeposit(address _token, uint256 _amount) onlyOwner nonReentrant external{
        require(validToken(_token), "MuchoProtocolGMX.notifyDeposit: token not supported");
        tokenAmountFromDeposits[_token] = tokenAmountFromDeposits[_token].add(_amount);
    }

    function validToken(address _token) internal view returns(bool){
        if(tokenList.contains(_token))
            return true;
        
        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            if(tokenToSecondaryTokens[tokenList.at(i)].contains(_token))
                return true;
        }
        return false;
    }

    function setRewardPercentages(RewardSplit calldata _split) onlyTraderOrAdmin external{
        require(_split.NftPercentage.add(_split.ownerPercentage) <= 10000, "MuchoProtocolGmx: NTF and owner fee are more than 100%");
        rewardSplit = RewardSplit({NftPercentage: _split.NftPercentage, ownerPercentage: _split.ownerPercentage});
    }

    function setCompoundProtocol(IMuchoProtocol _target) onlyTraderOrAdmin external{
        compoundProtocol = _target;
    }

    function getLastPeriodsApr(address _token) external view returns(int256[30] memory){
        return tokenAprInfo[_token].apr;
    }
    function getTokenInvested(address _token) public view returns(uint256){
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenUSDInvested(_token).mul(10**(30-18+decimals)).div(priceFeed.getPrice(_token));
        //return getTotalStaked(_token).sub(getTotalNotInvested(_token));
    }
    function getTokenNotInvested(address _token) public view returns(uint256){
        return IERC20(_token).balanceOf(address(this));
    }
    function getTokenStaked(address _token) public view returns(uint256){
        return getTokenNotInvested(_token).add(getTokenInvested(_token));
    }
    function getTokenUSDInvested(address _token) public view returns(uint256){
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        return fsGLP.balanceOf(address(this)).mul(priceFeed.getGLPprice()).div(10**(30-18+glpDecimals+4)).mul(glpWeight[_token]);
        //return getTotalInvested(_token).mul(priceFeed.getPrice(_token)).div(10**(30-18+decimals));
    }
    function getTokenUSDNotInvested(address _token) public view returns(uint256){
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenNotInvested(_token).mul(priceFeed.getPrice(_token)).div(10**(30-18+decimals));
    }
    function getTokenUSDStaked(address _token) public view returns(uint256){
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenStaked(_token).mul(priceFeed.getPrice(_token)).div(10**(30-18+decimals));
    }
    function getTokenWeight(address _token) external view returns(uint256){
        return glpWeight[_token];
    }

    function getTotalUSD() external view returns(uint256){
        (uint256 totalUsd,,) = getTotalUSDWithTokensUsd();
        return totalUsd;
    }
    function getTotalUSDWithTokensUsd() public view returns(uint256, uint256[] memory, uint256[] memory){
        //console.log("    SOL ***function getTotalUSDWithTokensUsd***");
        uint256 totalUsd = 0;
        uint256[] memory tokenUsds = new uint256[](tokenList.length());
        uint256[] memory tokenInvestedUsds = new uint256[](tokenList.length());

        //console.log("    SOL - getTotalUSDWithTokensUsd loop");
        for(uint256 i = 0; i < tokenList.length(); i = i.add(1)){
            address token = tokenList.at(i);
            //Add not invested balance
            //console.log("       SOL - token free usd", tokenUsd);
            //console.log("       SOL - token free balance and price", IERC20(token).balanceOf(address(this)), priceFeed.getPrice(token));
            //Add glp part
            tokenUsds[i] = getTokenUSDStaked(token);
            tokenInvestedUsds[i] = getTokenUSDInvested(token);

            totalUsd = totalUsd.add(tokenUsds[i]);
        }

        //console.log("    SOL ***END function getTotalUSDWithTokensUsd***");
        return (totalUsd, tokenUsds, tokenInvestedUsds);
    }

    function getTokenTotalUSD(address _token) public  view returns(uint256){
        console.log("    SOL - Getting totalGlpUsd");
        uint256 totalGlpUsd = fsGLP.balanceOf(address(this)).mul(priceFeed.getGLPprice());
        //Add not invested balance
        console.log("    SOL - Getting tokenUsd");
        uint256 tokenUsd = IERC20(_token).balanceOf(address(this)).mul(priceFeed.getPrice(_token));
        //Add glp part
        console.log("    SOL - Getting tokenUsd, adding glp part");
        tokenUsd = tokenUsd.add(totalGlpUsd.mul(glpWeight[_token]).div(10000));

        return tokenUsd;
    }

    /*----------------------------GLP mint and token conversion------------------------------*/

    function swapGLPto(uint256 _amount, address token, uint256 min_receive) private returns(uint256) {
        return glpRouter.unstakeAndRedeemGlp(token, _amount, min_receive, address(this));
    }

    //Mint GLP from token
    function swaptoGLP(uint256 _amount, address token) private returns(uint256) {
        IERC20(token).safeIncreaseAllowance(poolGLP, _amount);
        uint256 resGlp = glpRouter.mintAndStakeGlp(token, _amount,0, 0);
        console.log("    SOL - ***swaptoGLP*** (token, in, out)", address(token), _amount, resGlp);

        return resGlp;
    }


}