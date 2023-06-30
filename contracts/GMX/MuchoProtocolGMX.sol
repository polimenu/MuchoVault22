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
//import "./IMuchoGMXController.sol";
//import "../../lib/UintSafe.sol";

contract MuchoProtocolGMX is IMuchoProtocol, MuchoRoles, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint64;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet tokenList;
    mapping(address => uint256) tokenAmountFromDeposits;
    mapping(address => EnumerableSet.AddressSet) tokenToSecondaryTokens;
    uint256 lastWeightUpdate;

    uint256 public lastUpdate;

    function protocolName() public pure returns (string memory) {
        return "MuchoProtocolGMX";
    }

    function protocolDescription() public pure returns (string memory) {
        return
            "Performs a delta neutral strategy against GLP yield from GMX protocol";
    }

    uint256 public aprUpdatePeriod = 1 days;

    function setAprUpdatePeriod(uint256 _seconds) external onlyTraderOrAdmin {
        aprUpdatePeriod = _seconds;
    }

    uint256 public slippage = 30;

    function setSlippage(uint256 _slippage) external onlyTraderOrAdmin {
        require(_slippage >= 10 && _slippage <= 1000, "not in range");
        slippage = _slippage;
    }

    address public earningsAddress;
    function setEarningsAddress(address _earnings) external onlyAdmin {
        require(_earnings != address(0), "not valid");
        earningsAddress = _earnings;
    }

    //Claim esGmx, set false to save gas
    bool public claimEsGmx = false;

    function updateClaimEsGMX(bool _new) external onlyTraderOrAdmin {
        claimEsGmx = _new;
    }

    //GMX tokens - escrowed GMX and staked GLP
    IERC20 public EsGMX = IERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);

    function updateEsGMX(address _new) external onlyAdmin {
        EsGMX = IERC20(_new);
    }

    IERC20 public fsGLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);

    function updatefsGLP(address _new) external onlyAdmin {
        fsGLP = IERC20(_new);
    }

    IERC20 public WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    function updateWETH(address _new) external onlyAdmin {
        WETH = IERC20(_new);
    }

    //Interfaces to interact with GMX protocol

    //GLP Router:
    IGLPRouter public glpRouter =
        IGLPRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);

    function updateRouter(address _newRouter) external onlyAdmin {
        glpRouter = IGLPRouter(_newRouter);
    }

    //GLP Reward Router:
    IRewardRouter public glpRewardRouter =
        IRewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);

    function updateRewardRouter(address _newRouter) external onlyAdmin {
        glpRewardRouter = IRewardRouter(_newRouter);
    }

    //GLP Staking Pool address:
    address public poolGLP = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;

    function updatepoolGLP(address _newManager) external onlyAdmin {
        poolGLP = _newManager;
    }

    //GLP Vault
    IGLPVault public glpVault =
        IGLPVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);

    function updateGLPVault(address _newVault) external onlyAdmin {
        glpVault = IGLPVault(_newVault);
    }

    //MuchoRewardRouter Interaction for NFT Holders
    IMuchoRewardRouter public muchoRewardRouter =
        IMuchoRewardRouter(0x0000000000000000000000000000000000000000);

    function setMuchoRewardRouter(address _contract) external onlyAdmin {
        muchoRewardRouter = IMuchoRewardRouter(_contract);
    }

    RewardSplit public rewardSplit;
    IMuchoProtocol public compoundProtocol;

    // Safety not-invested margin min and desired (2 decimals)
    uint256 public minNotInvestedPercentage = 250;

    function setMinNotInvestedPercentage(
        uint256 _percent
    ) external onlyTraderOrAdmin {
        require(
            _percent < 9000 && _percent >= 0,
            "MuchoProtocolGMX: minNotInvestedPercentage not in range"
        );
        minNotInvestedPercentage = _percent;
    }

    uint256 public desiredNotInvestedPercentage = 500;

    function setDesiredNotInvestedPercentage(
        uint256 _percent
    ) external onlyTraderOrAdmin {
        require(
            _percent < 9000 && _percent >= 0,
            "MuchoProtocolGMX: desiredNotInvestedPercentage not in range"
        );
        desiredNotInvestedPercentage = _percent;
    }

    //If variation against desired weight is less than this, do not move:
    uint256 public minBasisPointsMove = 100;

    function setMinWeightBasisPointsMove(
        uint256 _percent
    ) external onlyTraderOrAdmin {
        require(
            _percent < 500 && _percent > 0,
            "MuchoProtocolGMX: minBasisPointsMove not in range"
        );
        minBasisPointsMove = _percent;
    }

    //Lapse to refresh weights when refreshing investment
    uint256 public maxRefreshWeightLapse = 1 days;

    function setMaxRefreshWeightLapse(uint256 _mw) external onlyTraderOrAdmin {
        require(_mw > 0, "MuchoProtocolGmx: Not valid lapse");
        maxRefreshWeightLapse = _mw;
    }

    IGLPPriceFeed public priceFeed;

    function setPriceFeed(IGLPPriceFeed _feed) external onlyAdmin {
        priceFeed = _feed;
    }

    function addToken(address _token) external onlyAdmin {
        tokenList.add(_token);
    }

    function addSecondaryToken(
        address _mainToken,
        address _secondary
    ) external onlyAdmin {
        tokenToSecondaryTokens[_mainToken].add(_secondary);
    }

    function removeSecondaryToken(
        address _mainToken,
        address _secondary
    ) external onlyAdmin {
        tokenToSecondaryTokens[_mainToken].remove(_secondary);
    }

    //Manual mode for desired weights (in automatic, gets it from GLP Contract):
    bool public manualModeWeights = false;

    function setManualModeWeights(bool _manual) external onlyTraderOrAdmin {
        manualModeWeights = _manual;
    }

    mapping(address => uint256) glpWeight;
    mapping(address => uint256) glpUsdgs;

    //Updates desired weights from GLP in automatic mode:
    function updateGlpWeights() public onlyOwnerTraderOrAdmin {
        //console.log("    SOL ***updateGlpWeights function***");
        require(!manualModeWeights, "MuchoProtocolGmx: manual mode");

        // Store all USDG value (deposit + secondary tokens) for each vault, and total USDG amount to divide later
        uint256 totalUsdg = getTotalAndUpdateVaultsUsdg();
        //console.log("    SOL - totalUsdg", totalUsdg);

        // Calculate weights for every vault
        uint256 totalWeight = 0;
        for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            uint256 vaultWeight = glpUsdgs[token].mul(10000).div(totalUsdg);
            glpWeight[token] = vaultWeight;
            totalWeight = totalWeight.add(vaultWeight);
        }

        // Check total weight makes sense
        uint256 diff = (totalWeight > 10000)
            ? (totalWeight - 10000)
            : (10000 - totalWeight);
        require(
            diff < 100,
            "MuchoProtocolGmx.updateDesiredWeightsFromGLP: Total weight far away from 1"
        );

        //Update date
        lastWeightUpdate = block.timestamp;
    }

    //Gets the total USDG in GLP and the USDG in GLP for each of our vaults' tokens:
    function getTotalAndUpdateVaultsUsdg() internal returns (uint256) {
        //console.log("   SOL - getTotalAndUpdateVaultsUsdg");
        uint256 totalUsdg;
        for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
            //console.log("   SOL - token", i);

            address token = tokenList.at(i);
            uint256 vaultUsdg = glpVault.usdgAmounts(token);
            //console.log("   SOL - token usdg", vaultUsdg);

            for (
                uint j = 0;
                j < tokenToSecondaryTokens[token].length();
                j = j.add(1)
            ) {
                uint256 secUsdg = glpVault.usdgAmounts(
                    tokenToSecondaryTokens[token].at(j)
                );
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
    function setWeight(
        address _token,
        uint256 _percent
    ) external onlyTraderOrAdmin {
        require(
            _percent < 7000 && _percent > 0,
            "MuchoProtocolGmx.setWeight: not in range"
        );
        require(
            manualModeWeights,
            "MuchoProtocolGmx.setWeight: automatic mode"
        );
        glpWeight[_token] = _percent;
    }

    function getMinTokenByWeight(
        uint256 _totalUsd,
        uint256[] memory _tokenUsd
    ) internal view returns (address, uint256) {
        uint maxDiff = 0;
        uint256 minUsd;
        address minToken;

        for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            if (glpWeight[token] > _tokenUsd[i].mul(10000).div(_totalUsd)) {
                uint diff = _totalUsd
                    .mul(glpWeight[token])
                    .div(_tokenUsd[i])
                    .sub(10000); //glpWeight[token].sub(_tokenUsd[i].mul(10000).div(_totalUsd));
                if (diff > maxDiff) {
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
    function refreshInvestment() external onlyOwnerTraderOrAdmin {
        //console.log("    SOL ***refreshInvestment function***");
        if (
            !manualModeWeights &&
            block.timestamp.sub(lastWeightUpdate) > maxRefreshWeightLapse
        ) {
            updateGlpWeights();
        }

        updateTokensInvestment();
    }

    function updateTokensInvestment() internal {
        //console.log("    SOL ***updateTokensInvested function***");
        (uint256 totalUsd, uint256[] memory tokenUsd, uint256[] memory tokenInvestedUsd) = getTotalUSDWithTokensUsd();
        //console.log("    SOL - totalUSD", totalUsd);
        //console.log("    SOL - tokenUSD0", tokenList.at(0), tokenUsd[0]);
        //console.log("    SOL - tokenUSD1", tokenList.at(1), tokenUsd[1]);
        //console.log("    SOL - tokenUSD2", tokenList.at(2), tokenUsd[2]);

        //Only can do delta neutral if all tokens are present
        if(tokenUsd[0] == 0 || tokenUsd[1] == 0 || tokenUsd[2] == 0){
            //console.log("    SOL - CANNOT INVEST SINCE A TOKEN HAS 0 VALUE");
            return;
        }

        (address minTokenByWeight, uint256 minTokenUsd) = getMinTokenByWeight(totalUsd, tokenUsd);
        //console.log("    SOL - minToken and USD", minTokenByWeight, minTokenUsd);

        //Calculate and do move for the minimum weight token
        doMinTokenWeightMove(minTokenByWeight);

        //Calc new total USD
        uint256 newTotalInvestedUsd = minTokenUsd
            .mul(10000 - desiredNotInvestedPercentage)
            .div(glpWeight[minTokenByWeight]);
        //console.log("    SOL - minTokenInvestedUsd - investedMin + weight", getTokenUSDInvested(minTokenByWeight), glpWeight[minTokenByWeight]);
        //console.log("    SOL - totalInvestedUsd", newTotalInvestedUsd);

        //Calculate move for every token different from the main one:
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);

            if (token != minTokenByWeight) {
                doNotMinTokenMove(
                    token,
                    tokenUsd[i],
                    tokenInvestedUsd[i],
                    newTotalInvestedUsd.mul(glpWeight[token]).div(10000)
                );
            }
        }

        lastUpdate = block.timestamp;
        //console.log("    SOL ***END updateTokensInvested function***");
    }


    function doMinTokenWeightMove(address _minTokenByWeight) internal {
        //console.log("    SOL ***doMinTokenWeightMove function***");
        uint256 totalBalance = getTokenStaked(_minTokenByWeight);
        uint256 notInvestedBalance = getTokenNotInvested(_minTokenByWeight);
        uint256 notInvestedBP = notInvestedBalance.mul(10000).div(totalBalance);
        //console.log("    SOL - Total balance", totalBalance);
        //console.log("    SOL - Not invested balance and BP and desiredBP", notInvestedBalance, notInvestedBP, desiredNotInvestedPercentage);

        //Invested less than desired:
        if (
            notInvestedBP > desiredNotInvestedPercentage &&
            notInvestedBP.sub(desiredNotInvestedPercentage) > minBasisPointsMove
        ) {
            uint256 amountToMove = notInvestedBalance.sub(
                desiredNotInvestedPercentage.mul(totalBalance).div(10000)
            );
            //console.log("    SOL - Swap token to GLP", _minTokenByWeight, amountToMove);
            swaptoGLP(amountToMove, _minTokenByWeight);
        }
        //Invested more than desired:
        else if (notInvestedBP < minNotInvestedPercentage) {
            uint256 glpAmount = tokenToGlp(
                _minTokenByWeight,
                desiredNotInvestedPercentage.mul(totalBalance).div(10000).sub(
                    notInvestedBalance
                )
            );
            //console.log("    SOL - Will swap GLP to (amount token)",glpAmount, _minTokenByWeight);
            swapGLPto(glpAmount, _minTokenByWeight, 0);
        }

        //console.log("    SOL ***END doMinTokenWeightMove function***");
    }

    //ToDo DEBUG - not working
    function doNotMinTokenMove(
        address _token,
        uint256 _totalTokenUSD,
        uint256 _currentUSDInvested,
        uint256 _newUSDInvested
    ) internal {
        //console.log("    SOL ***doNotMinTokenMove function*** (token)", _token);
        //console.log("    SOL    ***doNotMinTokenMove function*** (_totalTokenUSD, currentUSDInvested, newUSDInvested)", _totalTokenUSD, _currentUSDInvested, _newUSDInvested);

        //Invested less than desired:
        if (_newUSDInvested > _currentUSDInvested && _newUSDInvested.sub(_currentUSDInvested).mul(10000).div(_totalTokenUSD) > minBasisPointsMove) {
            uint256 amountToMove = usdToToken(_newUSDInvested.sub(_currentUSDInvested), _token);
            //console.log("    SOL - Investing more (amountToken)", amountToMove);
            swaptoGLP(amountToMove, _token);
        }
        //Invested more than desired:
        else if (
            _newUSDInvested < _currentUSDInvested &&
            _currentUSDInvested.sub(_newUSDInvested).mul(10000).div(
                _currentUSDInvested
            ) >
            minBasisPointsMove
        ) {
            uint256 glpAmount = usdToGlp(
                _currentUSDInvested.sub(_newUSDInvested)
            );
            //console.log("    SOL - Investing less (amountGlp)", glpAmount);
            swapGLPto(glpAmount, _token, 0);
        }

        //console.log("    SOL ***END doNotMinTokenMove function***");
    }

    function cycleRewards() external onlyOwnerTraderOrAdmin {
        if (claimEsGmx) {
            glpRewardRouter.claimEsGmx();
            uint256 balanceEsGmx = EsGMX.balanceOf(address(this));
            if (balanceEsGmx > 0) glpRewardRouter.stakeEsGmx(balanceEsGmx);
        }
        cycleRewardsETH();
    }

    //Get ETH rewards and distribute among the vaults and owner
    function cycleRewardsETH() private {
        //console.log("    SOL***cycleRewardsETH***");
        uint256 wethInit = WETH.balanceOf(address(this));
        //console.log("    SOL - wethInit", wethInit);
        //claim weth fees
        glpRewardRouter.claimFees();
        //console.log("    SOL - fees claimed");
        uint256 rewards = WETH.balanceOf(address(this)).sub(wethInit);
        //console.log("    SOL - rewards", rewards);
        //console.log("    SOL - nft and owner percentages", rewardSplit.NftPercentage, rewardSplit.ownerPercentage);

        if(rewards > 0){
            //use compoundPercentage to calculate the total amount and swap to GLP
            uint256 compoundAmount = rewards.mul(10000 - rewardSplit.NftPercentage - rewardSplit.ownerPercentage).div(10000);
            //console.log("    SOL - compoundAmount", compoundAmount);
            if (compoundProtocol == this) {
                //autocompound
                //console.log("    SOL - autocompounding");
                swaptoGLP(compoundAmount, address(WETH));
            } else {
                //console.log("    SOL - sending to another protocol");
                notInvestedTrySend(
                    address(WETH),
                    compoundAmount,
                    address(compoundProtocol)
                );
            }

            //use stakersPercentage to calculate the amount for rewarding stakers
            uint256 stakersAmount = rewards.mul(rewardSplit.NftPercentage).div(10000);
            //console.log("    SOL - stakersAmount", stakersAmount);
            WETH.approve(address(muchoRewardRouter), stakersAmount);
            muchoRewardRouter.depositRewards(address(WETH), stakersAmount);

            //send the rest to admin
            uint256 adminAmount = rewards.sub(compoundAmount).sub(stakersAmount);
            //console.log("    SOL - adminAmount", adminAmount);
            WETH.safeTransfer(earningsAddress, adminAmount);
        }
    }

    function withdrawAndSend(
        address _token,
        uint256 _amount,
        address _target
    ) external onlyOwner nonReentrant {
        require(
            _amount <= getTokenInvested(_token),
            "Cannot withdraw more than invested"
        );
        //console.log("    SOL ***withdrawAndSend***", _token, _amount);
        //console.log("    SOL - _amount", _amount);
        //console.log("    SOL - slippage", slippage);
        //console.log("    SOL - glpPrice", priceFeed.getGLPprice());
        //Total GLP to unstake

        uint256 glpOut = tokenToGlp(_token, _amount).mul(10000 + slippage).div(
            glpWeight[_token]
        );

        //console.log("    SOL - glpOut", glpOut);
        //console.log("    SOL - glpBal", fsGLP.balanceOf(address(this)));
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            address tk = tokenList.at(i);
            uint256 glpToTk = glpOut.mul(glpWeight[tk]).div(10000);
            //console.log("    SOL - unstaking GLP to primary token", tk, glpToTk);
            uint256 minReceive = (tk == _token) ? _amount : 0;
            //console.log("    SOL - minReceive", minReceive);
            //console.log("    SOL - balance desired token, before swap glp", IERC20(_token).balanceOf(address(this)));
            swapGLPto(glpToTk, tk, minReceive);
            //console.log("    SOL - balance desired token, after swap glp", IERC20(_token).balanceOf(address(this)));
        }

        //console.log("    SOL - balance", IERC20(_token).balanceOf(address(this)));
        //console.log("    SOL - transferring", _token, _amount);
        IERC20(_token).safeTransfer(_target, _amount);
        //console.log("    SOL ***END withdrawAndSend***");
    }

    function notInvestedTrySend(
        address _token,
        uint256 _amount,
        address _target
    ) public onlyOwner returns (uint256) {
        IERC20 tk = IERC20(_token);
        uint256 balance = tk.balanceOf(address(this));
        uint256 amountToTransfer = _amount;
        if (balance < _amount) amountToTransfer = balance;

        if (amountToTransfer <= tokenAmountFromDeposits[_token]) {
            tokenAmountFromDeposits[_token] =
                tokenAmountFromDeposits[_token] -
                amountToTransfer;
        } else {
            tokenAmountFromDeposits[_token] = 0;
        }

        tk.safeTransfer(_target, amountToTransfer);
        emit WithdrawnNotInvested(_token, _target, amountToTransfer);
        return amountToTransfer;
    }

    function notifyDeposit(
        address _token,
        uint256 _amount
    ) external onlyOwner nonReentrant {
        //console.log("    SOL***notifyDeposit***", _token, _amount);
        require(validToken(_token), "MuchoProtocolGMX.notifyDeposit: token not supported");
        tokenAmountFromDeposits[_token] = tokenAmountFromDeposits[_token].add(_amount);
    }

    function validToken(address _token) internal view returns (bool) {
        if (tokenList.contains(_token)) return true;

        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            if (tokenToSecondaryTokens[tokenList.at(i)].contains(_token))
                return true;
        }
        return false;
    }

    function setRewardPercentages(RewardSplit calldata _split) external onlyTraderOrAdmin {
        require(
            _split.NftPercentage.add(_split.ownerPercentage) <= 10000,
            "MuchoProtocolGmx: NTF and owner fee are more than 100%"
        );
        rewardSplit = RewardSplit({
            NftPercentage: _split.NftPercentage,
            ownerPercentage: _split.ownerPercentage
        });
    }

    function setCompoundProtocol(IMuchoProtocol _target) external onlyTraderOrAdmin {
        compoundProtocol = _target;
    }

    function getTokenInvested(address _token) public view returns (uint256) {
        return
            glpToToken(fsGLP.balanceOf(address(this)), _token)
                .mul(glpWeight[_token])
                .div(10000);
        //return getTotalStaked(_token).sub(getTotalNotInvested(_token));
    }

    function getTokenNotInvested(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function getTokenStaked(address _token) public view returns (uint256) {
        return getTokenNotInvested(_token).add(getTokenInvested(_token));
    }

    function getAllTokensStaked() public view returns (address[] memory, uint256[] memory) {
        address[] memory tkOut = new address[](tokenList.length());
        uint256[] memory amOut = new uint256[](tokenList.length());
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            tkOut[i] = tokenList.at(i);
            amOut[i] = getTokenStaked(tkOut[i]);
        }

        return (tkOut, amOut);
    }

    function getTokenUSDInvested(address _token) public view returns (uint256) {
        ////console.log("    SOL-***getTokenUSDInvested***", _token);
        return glpToUsd(fsGLP.balanceOf(address(this))).mul(glpWeight[_token]).div(10000);
    }

    function getTokenUSDNotInvested(
        address _token
    ) public view returns (uint256) {
        return tokenToUsd(_token, getTokenNotInvested(_token));
    }

    function getTokenUSDStaked(address _token) public view returns (uint256) {
        return tokenToUsd(_token, getTokenStaked(_token));
    }

    function getTokenWeight(address _token) external view returns (uint256) {
        return glpWeight[_token];
    }

    function getTotalUSD() external view returns (uint256) {
        (uint256 totalUsd, , ) = getTotalUSDWithTokensUsd();
        return totalUsd;
    }

    function getTotalInvestedUSD() external view returns (uint256) {
        uint256 tInvested = 0;
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            tInvested = tInvested.add(getTokenUSDInvested(tokenList.at(i)));
        }

        return tInvested;
    }

    function getTotalUSDWithTokensUsd() public view returns (uint256, uint256[] memory, uint256[] memory)
    {
        //console.log("    SOL ***function getTotalUSDWithTokensUsd***");
        uint256 totalUsd = 0;
        uint256[] memory tokenUsds = new uint256[](tokenList.length());
        uint256[] memory tokenInvestedUsds = new uint256[](tokenList.length());

        ////console.log("    SOL - getTotalUSDWithTokensUsd loop");
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);

            uint256 staked = getTokenUSDStaked(token);
            //console.log("    SOL - staked usd token amount", token, staked);
            tokenUsds[i] = staked;
            tokenInvestedUsds[i] = getTokenUSDInvested(token);
            //console.log("    SOL - invested usd token amount", token, tokenInvestedUsds[i]);

            totalUsd = totalUsd.add(tokenUsds[i]);
        }

        //console.log("    SOL ***END function getTotalUSDWithTokensUsd***");
        return (totalUsd, tokenUsds, tokenInvestedUsds);
    }

    /*----------------------------GLP mint and token conversion------------------------------*/

    function swapGLPto(
        uint256 _amountGlp,
        address token,
        uint256 min_receive
    ) private returns (uint256) {
        return
            glpRouter.unstakeAndRedeemGlp(
                token,
                _amountGlp,
                min_receive,
                address(this)
            );
    }

    function tokenToGlp(
        address _token,
        uint256 _amount
    ) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        return
            _amount
                .mul(priceFeed.getPrice(_token))
                .div(priceFeed.getGLPprice())
                .mul(10 ** glpDecimals)
                .div(10 ** decimals);
    }

    function glpToToken(
        uint256 _amountGlp,
        address _token
    ) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        return
            _amountGlp
                .mul(priceFeed.getGLPprice())
                .div(priceFeed.getPrice(_token))
                .mul(10 ** decimals)
                .div(10 ** glpDecimals);
    }

    function tokenToUsd(
        address _token,
        uint256 _amount
    ) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();

        return
            _amount.mul(priceFeed.getPrice(_token)).div(
                10 ** (30 - 18 + decimals)
            );
    }

    function usdToToken(
        uint256 _usdAmount,
        address _token
    ) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();

        return
            _usdAmount.mul(10 ** (30 - 18 + decimals)).div(
                priceFeed.getPrice(_token)
            );
    }

    function usdToGlp(uint256 _usdAmount) internal view returns (uint256) {
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        return
            _usdAmount.mul(10 ** (30 + glpDecimals - 18)).div(
                priceFeed.getGLPprice()
            );
    }

    function glpToUsd(uint256 _glpAmount) internal view returns (uint256) {
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        return _glpAmount.mul(priceFeed.getGLPprice()).div(10 ** (30 + glpDecimals - 18));
    }

    //Mint GLP from token
    function swaptoGLP(
        uint256 _amount,
        address token
    ) private returns (uint256) {
        IERC20(token).safeIncreaseAllowance(poolGLP, _amount);
        uint256 resGlp = glpRouter.mintAndStakeGlp(token, _amount, 0, 0);
        //console.log("    SOL - ***swaptoGLP*** (token, in, out)", address(token), _amount, resGlp);

        return resGlp;
    }
}
