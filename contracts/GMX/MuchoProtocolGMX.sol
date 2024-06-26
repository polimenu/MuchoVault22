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

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../../interfaces/IMuchoProtocol.sol';
import '../../interfaces/IPriceFeed.sol';
import '../../interfaces/IMuchoRewardRouter.sol';
import '../../interfaces/GMX/IGLPRouter.sol';
import '../../interfaces/GMX/IRewardRouter.sol';
import '../../interfaces/GMX/IGLPPriceFeed.sol';
import '../../interfaces/GMX/IGLPVault.sol';
import '../MuchoRoles.sol';

contract MuchoProtocolGMX is IMuchoProtocol, MuchoRoles, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint64;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    enum eFeeDestination {
        DEPOSIT,
        WITHDRAW,
        NONE
    }

    function protocolName() public pure returns (string memory) {
        return 'GMX delta-neutral strategy';
    }

    function protocolDescription() public pure returns (string memory) {
        return 'Performs a delta neutral strategy against GLP yield from GMX protocol';
    }

    function init() external onlyAdmin {
        glpApr = 1630;
        glpWethMintFee = 25;
        compoundProtocol = IMuchoProtocol(address(this));
        rewardSplit = RewardSplit({NftPercentage: 2000, ownerPercentage: 2000});
        grantRole(CONTRACT_OWNER, 0x7832fAb4F1d23754F89F30e5319146D16789c088);
        tokenList.add(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        tokenToSecondaryTokens[0xaf88d065e77c8cC2239327C5EDb3A432268e5831].add(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        tokenToSecondaryTokens[0xaf88d065e77c8cC2239327C5EDb3A432268e5831].add(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
        tokenToSecondaryTokens[0xaf88d065e77c8cC2239327C5EDb3A432268e5831].add(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
        tokenToSecondaryTokens[0xaf88d065e77c8cC2239327C5EDb3A432268e5831].add(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
        tokenList.add(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        tokenToSecondaryTokens[0x82aF49447D8a07e3bd95BD0d56f35241523fBab1].add(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);
        tokenToSecondaryTokens[0x82aF49447D8a07e3bd95BD0d56f35241523fBab1].add(0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0);
        tokenList.add(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    }

    /*---------------------------Variables--------------------------------*/
    //Last time rewards collected and values refreshed
    uint256 public lastUpdate = block.timestamp;

    //Desired weight (same GLP has) for every token
    mapping(address => uint256) public glpWeight;

    //Supported staked investment
    mapping(address => uint256) public amountStaked;

    //Client APRs for each token
    mapping(address => uint256) public aprToken;

    /*---------------------------Parameters--------------------------------*/

    //Where to send mint, burn, and backing fee
    eFeeDestination public mintFeeDestination = eFeeDestination.DEPOSIT;
    eFeeDestination public burnFeeDestination = eFeeDestination.WITHDRAW;
    eFeeDestination public backingFeeDestination = eFeeDestination.WITHDRAW;

    function updateFeeDestinations(eFeeDestination _burn, eFeeDestination _mint, eFeeDestination _backing) external onlyAdmin {
        burnFeeDestination = _burn;
        mintFeeDestination = _mint;
        backingFeeDestination = _backing;
    }

    //GLP Yield APR from GMX --> used to estimate our APR
    uint256 public glpApr;

    function updateGlpApr(uint256 _apr) external onlyTraderOrAdmin {
        glpApr = _apr;
        _updateAprs();
    }

    //GLP mint fee for weth --> used to estimate our APR
    uint256 public glpWethMintFee;

    function updateGlpWethMintFee(uint256 _fee) external onlyTraderOrAdmin {
        glpWethMintFee = _fee;
        _updateAprs();
    }

    //List of allowed tokens
    EnumerableSet.AddressSet tokenList;

    function addToken(address _token) external onlyAdmin {
        tokenList.add(_token);
    }

    function getTokens() external view returns (address[] memory) {
        address[] memory tk = new address[](tokenList.length());
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            tk[i] = tokenList.at(i);
        }
        return tk;
    }

    //Relation between a token and secondary for weight computing (eg. USDT and DAI can be secondary for USDC)
    mapping(address => EnumerableSet.AddressSet) tokenToSecondaryTokens;

    function addSecondaryToken(address _mainToken, address _secondary) external onlyAdmin {
        tokenToSecondaryTokens[_mainToken].add(_secondary);
    }

    function removeSecondaryToken(address _mainToken, address _secondary) external onlyAdmin {
        tokenToSecondaryTokens[_mainToken].remove(_secondary);
    }

    function getSecondaryTokens(address _mainToken) external view returns (address[] memory) {
        EnumerableSet.AddressSet storage secList = tokenToSecondaryTokens[_mainToken];
        address[] memory tk = new address[](secList.length());
        for (uint256 i = 0; i < secList.length(); i = i.add(1)) {
            tk[i] = secList.at(i);
        }
        return tk;
    }

    //Slippage we use when converting to GLP, to have a security gap with mint fees
    uint256 public slippage = 50;

    function setSlippage(uint256 _slippage) external onlyTraderOrAdmin {
        require(_slippage >= 10 && _slippage <= 1000, 'not in range');
        slippage = _slippage;
    }

    //Address where we send the owner profit
    address public earningsAddress = 0x829C145cE54A7f8c9302CD728310fdD6950B3e16;

    function setEarningsAddress(address _earnings) external onlyAdmin {
        require(_earnings != address(0), 'not valid');
        earningsAddress = _earnings;
    }

    //Claim esGmx, set false to save gas
    bool public claimEsGmx = false;

    function updateClaimEsGMX(bool _new) external onlyTraderOrAdmin {
        claimEsGmx = _new;
    }

    // Safety not-invested margin min and desired (2 decimals)
    uint256 public minNotInvestedPercentage = 250;

    function setMinNotInvestedPercentage(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 9000 && _percent >= 0, 'MuchoProtocolGMX: minNotInvestedPercentage not in range');
        minNotInvestedPercentage = _percent;
    }

    uint256 public desiredNotInvestedPercentage = 500;

    function setDesiredNotInvestedPercentage(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 9000 && _percent >= 0, 'MuchoProtocolGMX: desiredNotInvestedPercentage not in range');
        desiredNotInvestedPercentage = _percent;
    }

    //If variation against desired weight is less than this, do not move:
    uint256 public minBasisPointsMove = 100;

    function setMinWeightBasisPointsMove(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 500 && _percent > 0, 'MuchoProtocolGMX: minBasisPointsMove not in range');
        minBasisPointsMove = _percent;
    }

    //Lapse to refresh weights when refreshing investment
    uint256 public maxRefreshWeightLapse = 1 days;

    function setMaxRefreshWeightLapse(uint256 _mw) external onlyTraderOrAdmin {
        require(_mw > 0, 'MuchoProtocolGmx: Not valid lapse');
        maxRefreshWeightLapse = _mw;
    }

    //Manual mode for desired weights (in automatic, gets it from GLP Contract):
    bool public manualModeWeights = false;

    function setManualModeWeights(bool _manual) external onlyTraderOrAdmin {
        manualModeWeights = _manual;
    }

    //How do we split the rewards (percentages for owner and nft holders)
    RewardSplit public rewardSplit;

    function setRewardPercentages(RewardSplit calldata _split) external onlyTraderOrAdmin {
        require(_split.NftPercentage.add(_split.ownerPercentage) <= 10000, 'MuchoProtocolGmx: NTF and owner fee are more than 100%');
        rewardSplit = RewardSplit({NftPercentage: _split.NftPercentage, ownerPercentage: _split.ownerPercentage});
        _updateAprs();
    }

    // Additional manual deposit fee
    uint256 public additionalDepositFee = 0;

    function setAdditionalDepositFee(uint256 _fee) external onlyTraderOrAdmin {
        require(_fee <= 10000, 'MuchoProtocolGMX: setAdditionalDepositFee not in range');
        additionalDepositFee = _fee;
    }

    // Additional manual withdraw fee
    uint256 public additionalWithdrawFee = 0;

    function setAdditionalWithdrawFee(uint256 _fee) external onlyTraderOrAdmin {
        require(_fee <= 10000, 'MuchoProtocolGMX: setAdditionalWithdrawFee not in range');
        additionalWithdrawFee = _fee;
    }

    //Protocol where we compound the profits
    IMuchoProtocol public compoundProtocol;

    function setCompoundProtocol(IMuchoProtocol _target) external onlyTraderOrAdmin {
        compoundProtocol = _target;
    }

    /*---------------------------Contracts--------------------------------*/

    //GMX tokens - escrowed GMX and staked GLP
    IERC20 public EsGMX = IERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);

    function updateEsGMX(address _new) external onlyAdmin {
        EsGMX = IERC20(_new);
    }

    //Staked GLP
    IERC20 public fsGLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);

    function updatefsGLP(address _new) external onlyAdmin {
        fsGLP = IERC20(_new);
    }

    //WETH for the rewards
    IERC20 public WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    function updateWETH(address _new) external onlyAdmin {
        WETH = IERC20(_new);
    }

    //Interfaces to interact with GMX protocol

    //GLP Router:
    IGLPRouter public glpRouter = IGLPRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);

    function updateRouter(address _newRouter) external onlyAdmin {
        glpRouter = IGLPRouter(_newRouter);
    }

    //GLP Reward Router:
    IRewardRouter public glpRewardRouter = IRewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);

    function updateRewardRouter(address _newRouter) external onlyAdmin {
        glpRewardRouter = IRewardRouter(_newRouter);
    }

    //GLP Staking Pool address:
    address public poolGLP = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;

    function updatepoolGLP(address _newManager) external onlyAdmin {
        poolGLP = _newManager;
    }

    //GLP Vault
    IGLPVault public glpVault = IGLPVault(0x489ee077994B6658eAfA855C308275EAd8097C4A);

    function updateGLPVault(address _newVault) external onlyAdmin {
        glpVault = IGLPVault(_newVault);
    }

    //MuchoRewardRouter Interaction for NFT Holders
    IMuchoRewardRouter public muchoRewardRouter = IMuchoRewardRouter(0x570C2857CC624077070F7Bb1F10929aad658dA37);

    function setMuchoRewardRouter(address _contract) external onlyAdmin {
        muchoRewardRouter = IMuchoRewardRouter(_contract);
    }

    //GLP Price feed
    IGLPPriceFeed public priceFeed = IGLPPriceFeed(0x846ecf0462981CC0f2674f14be6Da2056Fc16bDA);

    function setPriceFeed(IGLPPriceFeed _feed) external onlyAdmin {
        priceFeed = _feed;
    }

    /*---------------------------Methods: trading interface--------------------------------*/

    //Updates weights, token investment, refreshes amounts and updates aprs:
    function refreshInvestment() external onlyOwnerTraderOrAdmin {
        //console.log("    SOL ***refreshInvestment function***");
        //updateStakedWithApr();
        updateTokensInvestment();
        _updateAprs();
    }

    //Cycles the rewards from GLP staking and compounds
    function cycleRewards() external onlyOwnerTraderOrAdmin {
        if (claimEsGmx) {
            glpRewardRouter.claimEsGmx();
            uint256 balanceEsGmx = EsGMX.balanceOf(address(this));
            if (balanceEsGmx > 0) glpRewardRouter.stakeEsGmx(balanceEsGmx);
        }
        cycleRewardsETH();
        _updateAprs();
    }

    //Withdraws a token amount from the not invested part. Withdraws the maximum possible up to the desired amount
    function notInvestedTrySend(address _token, uint256 _amount, address _target) public onlyOwner nonReentrant returns (uint256) {
        IERC20 tk = IERC20(_token);
        uint256 balance = tk.balanceOf(address(this));
        uint256 amountToTransfer = _amount;

        //console.log("    SOL - notInvestedTrySend", _token, balance, _amount);

        if (balance < _amount) amountToTransfer = balance;

        //console.log("    SOL - notInvestedTrySend amountToTransfer", amountToTransfer);

        amountStaked[_token] = amountStaked[_token].sub(amountToTransfer);
        tk.safeTransfer(_target, amountToTransfer);
        emit WithdrawnNotInvested(_token, _target, amountToTransfer, getTokenStaked(_token));

        //console.log("    SOL - notInvestedTrySend final balance", tk.balanceOf(address(this)));

        _updateAprs();

        return amountToTransfer;
    }

    //Withdraws a token amount from the invested part
    function withdrawAndSend(address _token, uint256 _amount, address _target) external onlyOwner nonReentrant {
        require(_amount <= getTokenInvested(_token), 'Cannot withdraw more than invested');

        //console.log("    SOL - withdrawAndSend", _token, _amount);
        //console.log("    SOL - withdrawAndSend amount desired to extract in usd", tokenToUsd(_token, _amount));
        //console.log("    SOL - withdrawAndSend amount to extract in usd", tokenToUsd(_token, _amount.mul(100000 + slippage)));

        //Total GLP to unstake
        uint256 amountAfterFees = _amount.sub(getWithdrawalFee(_token, _amount));
        uint256 glpOut = tokenToGlp(_token, amountAfterFees.mul(100000 + slippage).div(100000));
        swapGLPto(glpOut, _token, amountAfterFees);

        amountStaked[_token] = amountStaked[_token].sub(_amount);
        IERC20(_token).safeTransfer(_target, amountAfterFees);
        emit WithdrawnInvested(_token, _target, _amount, getTokenStaked(_token));
        _updateAprs();

        //console.log("    SOL - withdrawAndSend not invested after wd", getTokenUSDNotInvested(_token));
    }

    //Notification from the HUB of a deposit
    function deposit(address _token, uint256 _amount) external onlyOwner nonReentrant {
        require(validToken(_token), 'MuchoProtocolGMX.deposit: token not supported');
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 amountAfterFees = _amount.sub(getDepositFee(_token, _amount));
        amountStaked[_token] = amountStaked[_token].add(amountAfterFees);
        emit DepositNotified(msg.sender, _token, _amount, amountAfterFees, getTokenStaked(_token));
        //console.log("    SOL - MuchoProtocolGMX - deposited", _token, _amount, amountAfterFees);
        _updateAprs();
    }

    //Expected APR with current investment
    function getExpectedAPR(address _token, uint256 _additionalAmount) external view returns (uint256) {
        return _getExpectedAPR(_token, _additionalAmount);
    }

    function _getExpectedAPR(address _token, uint256 _additionalAmount) internal view returns (uint256) {
        //console.log("    SOL - getExpectedAPR", _token, _additionalAmount);
        uint256 sta = amountStaked[_token];
        uint256 notInv = getTokenNotInvested(_token);
        //console.log("    SOL - getExpectedAPR staked notInvested", sta, notInv);

        if (sta < notInv || sta.add(_additionalAmount) == 0) return 0;

        uint256 investedPctg = sta.sub(notInv).mul(10000).div(sta.add(_additionalAmount));
        uint256 compoundPctg = 10000 - rewardSplit.NftPercentage - rewardSplit.ownerPercentage;

        //console.log("    SOL - getExpectedAPR investedPctg compoundPctg", investedPctg, compoundPctg);
        //console.log("    SOL - getExpectedAPR glpApr glpWethMintFee", glpApr, glpWethMintFee);

        return glpApr.mul(compoundPctg).mul(10000 - glpWethMintFee).mul(investedPctg).div(10 ** 12);
    }

    function updateAprs() external onlyTraderOrAdmin {
        _updateAprs();
    }

    function _updateAprs() internal {
        updateStakedWithApr();
        for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            aprToken[token] = _getExpectedAPR(token, 0);
        }
    }

    function getExpectedNFTAnnualYield() external view returns (uint256) {
        return getTotalInvestedUSD().mul(glpApr).mul(rewardSplit.NftPercentage).div(100000000);
    }

    /*---------------------------Methods: token handling--------------------------------*/

    function convertToGLP(address _token) external onlyTraderOrAdmin {
        swaptoGLP(IERC20(_token).balanceOf(address(this)), _token);
    }

    //Sets manually the desired weight for a vault
    function setWeight(address _token, uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 7000 && _percent > 0, 'MuchoProtocolGmx.setWeight: not in range');
        require(manualModeWeights, 'MuchoProtocolGmx.setWeight: automatic mode');
        glpWeight[_token] = _percent;
    }

    function updateGlpWeights() external onlyTraderOrAdmin {
        _updateGlpWeights();
    }

    //Updates desired weights from GLP in automatic mode:
    function _updateGlpWeights() internal {
        //console.log("    ***********SOL updateGlpWeights*************");

        if (manualModeWeights) {
            return;
        }

        // Store all USDG value (deposit + secondary tokens) for each vault, and total USDG amount to divide later
        uint256 totalUsdg;
        uint256[] memory glpUsdgs = new uint256[](tokenList.length());
        for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            uint256 vaultUsdg = glpVault.usdgAmounts(token);
            //console.log("    SOL updateGlpWeights - usdgAmounts", token, vaultUsdg);

            for (uint j = 0; j < tokenToSecondaryTokens[token].length(); j = j.add(1)) {
                uint256 secUsdg = glpVault.usdgAmounts(tokenToSecondaryTokens[token].at(j));
                //console.log("    SOL updateGlpWeights - secusdgAmounts", token, secUsdg);
                vaultUsdg = vaultUsdg.add(secUsdg);
            }

            glpUsdgs[i] = vaultUsdg;
            totalUsdg = totalUsdg.add(vaultUsdg);
        }

        if (totalUsdg > 0) {
            //console.log("    SOL updateGlpWeights - TotalUsdg", totalUsdg);

            // Calculate weights for every vault
            uint256 totalWeight = 0;
            for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
                address token = tokenList.at(i);
                uint256 vaultWeight = glpUsdgs[i].div(1e8).div(totalUsdg.div(1e12));
                //console.log("    SOL updateGlpWeights - Weight for token", i, vaultWeight, glpUsdgs[i]);
                glpWeight[token] = vaultWeight;
                totalWeight = totalWeight.add(vaultWeight);
            }

            // Check total weight makes sense
            uint256 diff = (totalWeight > 10000) ? (totalWeight - 10000) : (10000 - totalWeight);
            require(diff < 100, 'MuchoProtocolGmx.updateDesiredWeightsFromGLP: Total weight far away from 1');
        }

        //console.log("    ***********END SOL updateGlpWeights*************");
    }

    /*----------------------------Public VIEWS to get the token amounts------------------------------*/

    function getDepositFee(address _token, uint256 _amount) public view returns (uint256) {
        uint256 totalDepFee = additionalDepositFee;
        if (mintFeeDestination == eFeeDestination.DEPOSIT) {
            totalDepFee = totalDepFee.add(getGlpDepositFee(_token, _amount));
        }
        if (burnFeeDestination == eFeeDestination.DEPOSIT) {
            totalDepFee = totalDepFee.add(getGlpWithdrawalFee(_token, _amount));
        }
        if (backingFeeDestination == eFeeDestination.DEPOSIT) {
            totalDepFee = totalDepFee.add(getBackingFee());
        }

        if (totalDepFee > 10000) totalDepFee = 10000;

        return _amount.mul(totalDepFee).div(10000);
    }

    function getWithdrawalFee(address _token, uint256 _amount) public view returns (uint256) {
        uint256 totalWdwFee = additionalWithdrawFee;
        if (mintFeeDestination == eFeeDestination.WITHDRAW) {
            totalWdwFee = totalWdwFee.add(getGlpDepositFee(_token, _amount));
        }
        if (burnFeeDestination == eFeeDestination.WITHDRAW) {
            totalWdwFee = totalWdwFee.add(getGlpWithdrawalFee(_token, _amount));
        }
        if (backingFeeDestination == eFeeDestination.WITHDRAW) {
            totalWdwFee = totalWdwFee.add(getBackingFee());
        }

        if (totalWdwFee > 10000) totalWdwFee = 10000;

        return _amount.mul(totalWdwFee).div(10000);
    }

    function getGlpDepositFee(address _token, uint256 _amount) public view returns (uint256) {
        uint256 mbFee = glpVault.mintBurnFeeBasisPoints();
        uint256 taxFee = glpVault.taxBasisPoints();
        uint256 price = priceFeed.getPrice(_token);
        uint8 dec = IERC20Metadata(_token).decimals();
        uint256 usdgDelta = _amount.mul(10 ** (30 + 18 - dec)).div(price);
        return glpVault.getFeeBasisPoints(_token, usdgDelta, mbFee, taxFee, true);
    }

    function getGlpWithdrawalFee(address _token, uint256 _amount) public view returns (uint256) {
        uint256 mbFee = glpVault.mintBurnFeeBasisPoints();
        uint256 taxFee = glpVault.taxBasisPoints();
        uint256 price = priceFeed.getPrice(_token);
        uint8 dec = IERC20Metadata(_token).decimals();
        uint256 usdgDelta = _amount.mul(10 ** (30 + 18 - dec)).div(price);
        return glpVault.getFeeBasisPoints(_token, usdgDelta, mbFee, taxFee, false);
    }

    //Amount of token that is invested
    function getTokenInvested(address _token) public view returns (uint256) {
        //console.log("   SOL - getTokenInvested", _token);
        uint256 notInv = getTokenNotInvested(_token);
        uint256 sta = getTokenStaked(_token);
        if (sta < notInv) return 0;
        unchecked {
            return sta - notInv;
        }
    }

    //Amount of token that is not invested
    function getTokenNotInvested(address _token) public view returns (uint256) {
        //console.log("   SOL - getTokenNotInvested", _token);
        return IERC20(_token).balanceOf(address(this));
    }

    //Total Amount of token (invested + not)
    function getTokenStaked(address _token) public view returns (uint256) {
        //console.log("   SOL - getTokenStaked", _token);
        //console.log("   SOL - getTokenStaked lastUpdate now", lastUpdate, block.timestamp);
        uint256 timeDiff = block.timestamp.sub(lastUpdate);
        uint256 earn = amountStaked[_token].mul(aprToken[_token]).mul(timeDiff).div(365 days).div(10000);
        //console.log("   SOL - getTokenStaked staked apr", amountStaked[_token], aprToken[_token]);

        //console.log("   SOL - getTokenStaked timeDiff earn", timeDiff, earn);
        return amountStaked[_token].add(earn);
    }

    //List of total Amount of token (invested + not) for all tokens
    function getAllTokensStaked() public view returns (address[] memory, uint256[] memory) {
        address[] memory tkOut = new address[](tokenList.length());
        uint256[] memory amOut = new uint256[](tokenList.length());
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            tkOut[i] = tokenList.at(i);
            amOut[i] = getTokenStaked(tkOut[i]);
        }

        return (tkOut, amOut);
    }

    //USD value of token that is invested
    function getTokenUSDInvested(address _token) public view returns (uint256) {
        //console.log("   SOL - getTokenUSDInvested", _token);
        return tokenToUsd(_token, getTokenInvested(_token));
    }

    //USD value of token that is NOT invested
    function getTokenUSDNotInvested(address _token) public view returns (uint256) {
        //console.log("   SOL - getTokenUSDNotInvested", _token);
        return tokenToUsd(_token, getTokenNotInvested(_token));
    }

    //Total USD value of token (invested + not)
    function getTokenUSDStaked(address _token) public view returns (uint256) {
        //console.log("   SOL - getTokenUSDStaked", _token);
        return tokenToUsd(_token, getTokenStaked(_token));
    }

    //Invested weight for a token vault
    function getTokenWeight(address _token) external view returns (uint256) {
        //console.log("   SOL - getTokenWeight", _token);
        uint256 totUsd = getTotalInvestedUSD();
        if (totUsd == 0) return 0;

        return getTokenUSDInvested(_token).mul(10000).div(totUsd);
    }

    //Total USD value (invested + not)
    function getTotalUSD() public view returns (uint256) {
        (uint256 totalUsd, , ) = getTotalUSDWithTokensUsd();
        return totalUsd;
    }

    //Invested USD value for all tokens
    function getTotalInvestedUSD() public view returns (uint256) {
        //console.log("   SOL - getTotalInvestedUSD");
        uint256 tInvested = 0;
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            tInvested = tInvested.add(getTokenUSDInvested(tokenList.at(i)));
        }

        return tInvested;
    }

    //Total USD value for all tokens + lists of total usd and invested usd for each token
    function getTotalUSDWithTokensUsd() public view returns (uint256, uint256[] memory, uint256[] memory) {
        uint256 totalUsd = 0;
        uint256[] memory tokenUsds = new uint256[](tokenList.length());
        uint256[] memory tokenInvestedUsds = new uint256[](tokenList.length());

        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            uint256 staked = getTokenUSDStaked(token);
            /*uint256 notInv = getTokenUSDNotInvested(token);
            if(staked < notInv)
                staked = notInv;*/
            tokenUsds[i] = staked;
            tokenInvestedUsds[i] = getTokenUSDInvested(token);
            totalUsd = totalUsd.add(staked);
        }

        return (totalUsd, tokenUsds, tokenInvestedUsds);
    }

    //Gets the total USD amount backed
    function getTotalUSDBacked() public view returns (uint256) {
        uint256 totalUsd = 0;

        //Add not invested part (ERC20 tokens balance of the contract)
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            totalUsd = totalUsd.add(getTokenUSDNotInvested(tokenList.at(i)));
        }

        //Add GLP backing
        totalUsd = totalUsd.add(glpToUsd(getGLPBalance()));

        return totalUsd;
    }

    //Gets the GLP balance of the contract
    function getGLPBalance() public view returns (uint256) {
        return fsGLP.balanceOf(address(this));
    }

    //Gets backing percentage
    function getBacking() public view returns (uint256 backing) {
        uint256 stakedUsd = getTotalUSD();
        uint256 backedUsd = getTotalUSDBacked();

        backing = backedUsd.mul(10000).div(stakedUsd);
    }

    //Gets backing fee
    function getBackingFee() public view returns (uint256 fee) {
        uint256 backing = getBacking();

        if (backing > 10000) {
            fee = 0;
        } else {
            fee = 10000 - backing;
        }
    }

    /*---------------------------INTERNAL Methods--------------------------------*/

    //Adds apr to staked value
    function updateStakedWithApr() internal {
        uint256 timeDiff = block.timestamp.sub(lastUpdate);
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);

            uint256 earn = amountStaked[token].mul(aprToken[token]).mul(timeDiff).div(365 days).div(10000);
            amountStaked[token] = amountStaked[token].add(earn);
        }

        lastUpdate = block.timestamp;
    }

    //Updates the investment part for each token according to the desired weights
    function updateTokensInvestment() internal {
        (uint256 totalUsd, uint256[] memory tokenUsd, uint256[] memory tokenInvestedUsd) = getTotalUSDWithTokensUsd();
        _updateGlpWeights();

        //Only can do delta neutral if all tokens are present
        if (tokenUsd[0] == 0 || tokenUsd[1] == 0 || tokenUsd[2] == 0) {
            return;
        }

        (address minTokenByWeight, uint256 minTokenUsd) = getMinTokenByWeight(totalUsd, tokenUsd);

        //Calculate and do move for the minimum weight token
        doMinTokenWeightMove(minTokenByWeight);

        //Calc new total USD
        uint256 newTotalInvestedUsd = minTokenUsd.mul(10000 - desiredNotInvestedPercentage).div(glpWeight[minTokenByWeight]);

        //console.log("    SOL updateTokensInvestment - New total invested desired", newTotalInvestedUsd, minTokenUsd, glpWeight[minTokenByWeight]);

        //Calculate move for every token different from the main one:
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);

            if (token != minTokenByWeight) {
                doNotMinTokenMove(token, tokenUsd[i], tokenInvestedUsd[i], newTotalInvestedUsd.mul(glpWeight[token]).div(10000));
            }
        }
    }

    //Gets the token more far away from the desired weight, will be the one more invested and will point our global investment position
    function getMinTokenByWeight(uint256 _totalUsd, uint256[] memory _tokenUsd) internal view returns (address, uint256) {
        uint maxDiff = 0;
        uint256 minUsd;
        address minToken;

        for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            if (glpWeight[token] > _tokenUsd[i].mul(10000).div(_totalUsd)) {
                uint diff = _totalUsd.mul(glpWeight[token]).div(_tokenUsd[i]).sub(10000); //glpWeight[token].sub(_tokenUsd[i].mul(10000).div(_totalUsd));
                if (diff > maxDiff) {
                    minToken = token;
                    minUsd = _tokenUsd[i];
                    maxDiff = diff;
                }
            }
        }

        return (minToken, minUsd);
    }

    //Moves the min token to the desired min invested percentage
    function doMinTokenWeightMove(address _minTokenByWeight) internal {
        uint256 totalBalance = getTokenStaked(_minTokenByWeight);
        uint256 notInvestedBalance = getTokenNotInvested(_minTokenByWeight);
        if (notInvestedBalance > totalBalance)
            //Do not use more than total staked for clients
            notInvestedBalance = totalBalance;
        uint256 notInvestedBP = notInvestedBalance.mul(10000).div(totalBalance);
        //console.log("    SOL - doMinTokenWeightMove totalBal, notInvested, notInvestedBP", tokenToUsd(_minTokenByWeight, totalBalance), tokenToUsd(_minTokenByWeight, notInvestedBalance), notInvestedBP);
        //console.log("    SOL - doMinTokenWeightMove desiredNotInvestedPercentage", desiredNotInvestedPercentage);

        //Invested less than desired:
        if (notInvestedBP > desiredNotInvestedPercentage && notInvestedBP.sub(desiredNotInvestedPercentage) > minBasisPointsMove) {
            uint256 amountToMove = notInvestedBalance.sub(desiredNotInvestedPercentage.mul(totalBalance).div(10000));
            //console.log("    SOL - doMinTokenWeightMove INVESTING", tokenToUsd(_minTokenByWeight, amountToMove), _minTokenByWeight);
            swaptoGLP(amountToMove, _minTokenByWeight);
        }
        //Invested more than desired:
        else if (notInvestedBP < minNotInvestedPercentage) {
            uint256 glpAmount = tokenToGlp(_minTokenByWeight, desiredNotInvestedPercentage.mul(totalBalance).div(10000).sub(notInvestedBalance));
            //console.log("    SOL - doMinTokenWeightMove UNINVESTING GLP", tokenToUsd(_minTokenByWeight, desiredNotInvestedPercentage.mul(totalBalance).div(10000).sub(notInvestedBalance)), _minTokenByWeight);
            swapGLPto(glpAmount, _minTokenByWeight, 0);
        }

        //console.log("    SOL - doMinTokenWeightMove notInvested after move", getTokenUSDNotInvested(_minTokenByWeight));
        //console.log("    SOL - doMinTokenWeightMove invested after move", getTokenUSDInvested(_minTokenByWeight));
    }

    //Moves a token which is not the min
    function doNotMinTokenMove(address _token, uint256 _totalTokenUSD, uint256 _currentUSDInvested, uint256 _newUSDInvested) internal {
        //console.log("    SOL - doNotMinTokenMove", _token, _totalTokenUSD, _currentUSDInvested);
        //console.log("    SOL - doNotMinTokenMove _newUSDInvested", _newUSDInvested);

        //Invested less than desired:
        if (_newUSDInvested > _currentUSDInvested && _newUSDInvested.sub(_currentUSDInvested).mul(10000).div(_totalTokenUSD) > minBasisPointsMove) {
            uint256 usdToMove = _newUSDInvested.sub(_currentUSDInvested);
            uint256 amountToMove = usdToToken(usdToMove, _token);
            //console.log("    SOL - doNotMinTokenMove INVESTING", usdToMove, amountToMove);
            swaptoGLP(amountToMove, _token);
        }
        //Invested more than desired:
        else if (
            _newUSDInvested < _currentUSDInvested && _currentUSDInvested.sub(_newUSDInvested).mul(10000).div(_currentUSDInvested) > minBasisPointsMove
        ) {
            uint256 glpAmount = usdToGlp(_currentUSDInvested.sub(_newUSDInvested));
            //console.log("    SOL - doNotMinTokenMove UNINVESTING", glpToUsd(glpAmount));
            swapGLPto(glpAmount, _token, 0);
        }
        //else{
        //   //console.log("    SOL - doNotMinTokenMove NOT MOVING!");
        //}
    }

    //Get WETH rewards and distribute among the vaults and owner
    function cycleRewardsETH() private {
        uint256 wethInit = WETH.balanceOf(address(this));

        //claim weth fees
        glpRewardRouter.claimFees();
        uint256 rewards = WETH.balanceOf(address(this)).sub(wethInit);

        if (rewards > 0) {
            //console.log("    SOL - WETH init", wethInit);
            //console.log("    SOL - WETH rewards", rewards);
            //console.log("    SOL - NFT percentage", rewardSplit.NftPercentage);
            //console.log("    SOL - Owner percentage", rewardSplit.ownerPercentage);
            //use compoundPercentage to calculate the total amount and swap to GLP
            uint256 compoundAmount = rewards.mul(10000 - rewardSplit.NftPercentage - rewardSplit.ownerPercentage).div(10000);
            //console.log("    SOL - Compound amount", compoundAmount);
            if (compoundProtocol == this) {
                swaptoGLP(compoundAmount, address(WETH));
            } else {
                notInvestedTrySend(address(WETH), compoundAmount, address(compoundProtocol));
            }

            //console.log("    SOL - WETH after swap to glp", WETH.balanceOf(address(this)));

            //use stakersPercentage to calculate the amount for rewarding stakers
            uint256 stakersAmount = rewards.mul(rewardSplit.NftPercentage).div(10000);
            WETH.approve(address(muchoRewardRouter), stakersAmount);
            //console.log("    SOL - dspositing amount for NFT", stakersAmount);
            muchoRewardRouter.depositRewards(address(WETH), stakersAmount);

            //console.log("    SOL - WETH after sending to nft", WETH.balanceOf(address(this)));

            //send the rest to admin
            uint256 adminAmount = rewards.sub(compoundAmount).sub(stakersAmount);
            WETH.safeTransfer(earningsAddress, adminAmount);

            //console.log("    SOL - WETH after swap to owner", WETH.balanceOf(address(this)));
        }
    }

    //Validates a token
    function validToken(address _token) internal view returns (bool) {
        if (tokenList.contains(_token)) return true;

        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            if (tokenToSecondaryTokens[tokenList.at(i)].contains(_token)) return true;
        }
        return false;
    }

    /*----------------------------Internal token conversion methods------------------------------*/

    function tokenToGlp(address _token, uint256 _amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        return _amount.mul(priceFeed.getPrice(_token)).div(priceFeed.getGLPprice()).mul(10 ** glpDecimals).div(10 ** (decimals + 18));
    }

    function glpToToken(uint256 _amountGlp, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        //console.log("glpToToken getPrice", priceFeed.getPrice(_token));

        return _amountGlp.mul(priceFeed.getGLPprice()).mul(10 ** (decimals + 18)).div(priceFeed.getPrice(_token)).div(10 ** glpDecimals);
    }

    function tokenToUsd(address _token, uint256 _amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _amount.mul(priceFeed.getPrice(_token)).div(10 ** (12 + decimals));
    }

    function usdToToken(uint256 _usdAmount, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _usdAmount.mul(10 ** decimals).div(priceFeed.getPrice(_token).div(10 ** 12));
    }

    function usdToGlp(uint256 _usdAmount) internal view returns (uint256) {
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();
        return _usdAmount.mul(10 ** glpDecimals).div(10 ** 6).div(priceFeed.getGLPprice());
    }

    function glpToUsd(uint256 _glpAmount) internal view returns (uint256) {
        uint8 glpDecimals = IERC20Metadata(address(fsGLP)).decimals();

        return _glpAmount.mul(priceFeed.getGLPprice()).mul(10 ** 6).div(10 ** glpDecimals);
    }

    /*----------------------------GLP mint and token conversion------------------------------*/

    function swapGLPto(uint256 _amountGlp, address token, uint256 min_receive) private returns (uint256) {
        if (_amountGlp > 0) {
            uint256 glpBal = fsGLP.balanceOf(address(this));
            if (_amountGlp > glpBal) _amountGlp = glpBal;

            return glpRouter.unstakeAndRedeemGlp(token, _amountGlp, min_receive, address(this));
        }
        return 0;
    }

    //Mint GLP from token
    function swaptoGLP(uint256 _amount, address token) private returns (uint256) {
        if (_amount > 0) {
            uint256 bal = IERC20(token).balanceOf(address(this));
            if (_amount > bal) _amount = bal;

            IERC20(token).safeIncreaseAllowance(poolGLP, _amount);
            uint256 resGlp = glpRouter.mintAndStakeGlp(token, _amount, 0, 0);

            //console.log("********ADD GLP***********", resGlp, prevGlp, fsGLP.balanceOf(address(this)));

            return resGlp;
        }

        return 0;
    }
}
