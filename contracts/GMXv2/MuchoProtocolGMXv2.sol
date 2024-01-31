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
import '../../lib/GmPool.sol';
import '../../interfaces/IPriceFeed.sol';
import '../../interfaces/IMuchoRewardRouter.sol';
import '../../interfaces/GMX/IGLPRouter.sol';
import '../../interfaces/GMX/IRewardRouter.sol';
import '../../interfaces/GMX/IGLPPriceFeed.sol';
import '../../interfaces/GMX/IGLPVault.sol';
import '../../interfaces/GMXv2/IMuchoProtocolGMXv2Logic.sol';
import '../../interfaces/GMXv2/IGmxV2ExchangeRouter.sol';
import '../MuchoRoles.sol';

contract MuchoProtocolGMXv2 is IMuchoProtocol, MuchoRoles, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint64;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    function protocolName() public pure returns (string memory) {
        return 'GMX V2 delta-neutral strategy';
    }

    function protocolDescription() public pure returns (string memory) {
        return 'Performs a delta neutral strategy against GM tokens yield from GMX protocol (v2)';
    }

    function init() external onlyAdmin {
        gmWethMintFee = 25;
        compoundProtocol = IMuchoProtocol(address(this));
        rewardSplit = RewardSplit({NftPercentage: 2000, ownerPercentage: 2000});
        grantRole(CONTRACT_OWNER, 0x7832fAb4F1d23754F89F30e5319146D16789c088); //MuchoHUB
        tokenList.add(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); //USDC
        tokenList.add(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); //WETH
        tokenList.add(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f); //WBTC
        //GM WETH-USDC
        addPool(
            0x70d95587d40A2caf56bd97485aB3Eec10Bee6336,
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            true,
            0xd795542d99d4dc3faa6f4e4a11da9347d4f58fcfce910ccd9878f8fd79234324,
            0x4a0e3a43fc8a8e48629f6d4e1c0c1ae7098a35d9834cd0c13446fc2b802a24a7
        );
        //GM WBTC-USDC
        addPool(
            0x47c031236e19d024b42f8AE6780E44A573170703,
            0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f,
            true,
            0x695ec0e29327f505d4955e89ec25f98741aedf22d209dbc35e1d2d61e683877c,
            0x6805e3bd65fab2c6cda687df591a5e9011a99df2ff0aa98287114c693ef8583e
        );
    }

    /*---------------------------Variables--------------------------------*/
    //Last time rewards collected and values refreshed
    uint256 public lastUpdate = block.timestamp;

    //Supported staked investment for every token
    mapping(address => uint256) public amountStaked;

    //Client APRs for each token
    mapping(address => uint256) public aprToken;

    /*---------------------------Parameters--------------------------------*/

    //GM Pools and operations
    GmPool[] public gmPools;

    function addPool(address _addr, address _long, bool _enabled, bytes32 positiveSwapFee, bytes32 negativeSwapFee) external onlyAdmin {
        require(!existsEnabledPool(_addr, _long), 'MuchoProtocolGmxV2: pool already exists');
        require(oracleHas(_long), 'MuchoProtocolGmxV2: Oracle does not control long token');
        require(oracleHas(_addr), 'MuchoProtocolGmxV2: Oracle does not control GM token');

        uint256 longWeigth = calculateLongWeight(_addr, _long, shortToken);
        require(longWeight < 9500, 'MuchoProtocolGmxV2: Long weight more than 95%');
        require(longWeight > 500, 'MuchoProtocolGmxV2: Long less more than 5%');

        gmPools.add(
            GmPool({
                gmAddress: _addr,
                long: _long,
                longWeight: longWeight,
                enabled: _enabled,
                gmApr: 0,
                positiveSwapFee: positiveSwapFee,
                negativeSwapFee: negativeSwapFee
            })
        );
    }

    function setEnabledPool(uint256 _pool, bool _enabled) external onlyAdmin {
        gmPools[_pool].enabled = _enabled;
    }

    //GM token Yield APR from GMX --> used to estimate our APR
    function updateGmApr(uint256 _pool, uint256 _apr) external onlyTraderOrAdmin {
        gmPools[_pool].gmApr = _apr;
        _updateAprs();
    }

    //GM mint fee for weth --> used to estimate our APR
    uint256 public gmWethMintFee;

    function updateGmWethMintFee(uint256 _fee) external onlyTraderOrAdmin {
        gmWethMintFee = _fee;
        _updateAprs();
    }

    //List of allowed tokens to deposit
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

    //Slippage we use when selling GM, to have a security gap with mint fees
    uint256 public slippage = 50;

    function setSlippage(uint256 _slippage) external onlyTraderOrAdmin {
        require(_slippage >= 10 && _slippage <= 1000, 'not in range');
        slippage = _slippage;
    }

    //Address where we send the owner profit
    address public earningsAddress = 0x66C9269d75AB52941E325D9c1E3b156A325e8a90;

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
        require(_percent < 9000 && _percent >= 0, 'MuchoProtocolGMXv2: minNotInvestedPercentage not in range');
        minNotInvestedPercentage = _percent;
    }

    uint256 public desiredNotInvestedPercentage = 500;

    function setDesiredNotInvestedPercentage(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 9000 && _percent >= 0, 'MuchoProtocolGMXv2: desiredNotInvestedPercentage not in range');
        desiredNotInvestedPercentage = _percent;
    }

    //If variation against desired weight is less than this, do not move:
    uint256 public minBasisPointsMove = 100;

    function setMinWeightBasisPointsMove(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 500 && _percent > 0, 'MuchoProtocolGMXv2: minBasisPointsMove not in range');
        minBasisPointsMove = _percent;
    }

    //Lapse to refresh weights when refreshing investment
    uint256 public maxRefreshWeightLapse = 1 days;

    function setMaxRefreshWeightLapse(uint256 _mw) external onlyTraderOrAdmin {
        require(_mw > 0, 'MuchoProtocolGmxv2: Not valid lapse');
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
        require(_split.NftPercentage.add(_split.ownerPercentage) <= 10000, 'MuchoProtocolGmxv2: NTF and owner fee are more than 100%');
        rewardSplit = RewardSplit({NftPercentage: _split.NftPercentage, ownerPercentage: _split.ownerPercentage});
        _updateAprs();
    }

    // Additional manual deposit fee
    uint256 public additionalDepositFee = 0;

    function setAdditionalDepositFee(uint256 _fee) external onlyTraderOrAdmin {
        require(_fee < 20, 'MuchoProtocolGMXv2: setAdditionalDepositFee not in range');
        additionalDepositFee = _fee;
    }

    // Additional manual withdraw fee
    uint256 public additionalWithdrawFee = 0;

    function setAdditionalWithdrawFee(uint256 _fee) external onlyTraderOrAdmin {
        require(_fee < 20, 'MuchoProtocolGMXv2: setAdditionalWithdrawFee not in range');
        additionalWithdrawFee = _fee;
    }

    //Protocol where we compound the profits
    IMuchoProtocol public compoundProtocol;

    function setCompoundProtocol(IMuchoProtocol _target) external onlyTraderOrAdmin {
        compoundProtocol = _target;
    }

    /*---------------------------Contracts--------------------------------*/

    //Short token
    IERC20 public shortToken = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    function updateShortToken(address _new) external onlyAdmin {
        shortToken = IERC20(_new);
    }

    //Weight logic contract
    IMuchoProtocolGMXv2Logic public muchoGmxV2Logic;

    function updateMuchoLogic(address _new) external onlyAdmin {
        muchoGmxV2Logic = IMuchoProtocolGMXv2Logic(_new);
    }

    //GMX tokens - escrowed GMX and staked GLP
    IERC20 public EsGMX = IERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);

    function updateEsGMX(address _new) external onlyAdmin {
        EsGMX = IERC20(_new);
    }

    //WETH for the rewards
    IERC20 public WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    function updateWETH(address _new) external onlyAdmin {
        WETH = IERC20(_new);
    }

    //Interfaces to interact with GMX protocol

    //Exchange Router:
    IGmxV2ExchangeRouter public exchangeRouter = IGmxV2ExchangeRouter(0x7c68c7866a64fa2160f78eeae12217ffbf871fa8);

    function updateRouter(address _newRouter) external onlyAdmin {
        exchangeRouter = IGmxV2ExchangeRouter(_newRouter);
    }

    //GMX Reward Router:
    IRewardRouter public gmxRewardRouter = IRewardRouter(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);

    function updateRewardRouter(address _newRouter) external onlyAdmin {
        gmxRewardRouter = IRewardRouter(_newRouter);
    }

    //GMX Router address
    address public gmxRouter = 0x7452c558d45f8afc8c83dae62c3f8a5be19c71f6;

    function updateGmxRouter(address _newRouter) external onlyAdmin {
        gmxRouter = _newRouter;
    }

    //Execution fee keepers from GMX
    uint256 EXECUTIONFEE_KEEPERS = 1086250000000000;

    //GMX Deposit Vault:
    address public gmxDepositVault = 0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55;

    function updateGmxDepositVault(address _newManager) external onlyAdmin {
        gmxDepositVault = _newManager;
    }

    //GMX Withdrawal Vault:
    address public gmxWithdrawalVault = 0x0628D46b5D145f183AdB6Ef1f2c97eD1C4701C55;

    function updateGmxWithdrawalVault(address _newManager) external onlyAdmin {
        gmxWithdrawalVault = _newManager;
    }

    //MuchoRewardRouter Interaction for NFT Holders
    IMuchoRewardRouter public muchoRewardRouter = IMuchoRewardRouter(0x570C2857CC624077070F7Bb1F10929aad658dA37);

    function setMuchoRewardRouter(address _contract) external onlyAdmin {
        muchoRewardRouter = IMuchoRewardRouter(_contract);
    }

    //Price feed
    IGmxV2PriceFeed public priceFeed;

    function setPriceFeed(IGmxV2PriceFeed _feed) external onlyAdmin {
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
            gmxRewardRouter.claimEsGmx();
            uint256 balanceEsGmx = EsGMX.balanceOf(address(this));
            if (balanceEsGmx > 0) gmxRewardRouter.stakeEsGmx(balanceEsGmx);
        }
        cycleRewardsETH();
        _updateAprs();
    }

    //For safety reasons, function to withdraw any token that fell off here by mistake
    function transferToken(address _token, address_to) external onlyAdmin {
        IERC20(_token).transfer(_to, IERC20(_token).balanceOf(address(this)));
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

        //Calc usd investment per pool and total usd investment, to ponderate:
        (uint256[] usdP, uint256 totUsdP) = usdFromPoolsWhereTokenIs(_token);

        //Withdraw:
        for (uint256 i = 0; i < gmPools.length; i++) {
            if (gmPools[i].enabled && usdP[i] > 0) {
                uint256 usdOutFromPool = (usdOut * usdP[i]) / totUsdP;
                uint256 usdToWithdraw = usdOutFromPool.mul(100000 + slippage).div(100000);
                uint256 gmTokenAmountToWithdraw = (usdToWithdraw * gmTokenUsdValue(i, 10000)) / 10000;
                swapGMTokenTo(i, _token, gmTokenAmountToWithdraw);
            }
        }
    }

    //Notification from the HUB of a deposit
    function deposit(address _token, uint256 _amount) external onlyOwner nonReentrant {
        require(validToken(_token), 'MuchoProtocolGMXv2.deposit: token not supported');
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
        //console.log("    SOL - getExpectedAPR glpApr gmWethMintFee", glpApr, gmWethMintFee);
        uint256 totalInv;
        uint256 ponderatedApr;
        bool isShortToken = (address(shortToken) == _token);
        for (uint256 i = 0; i < gmPools.length; i++) {
            if (gmPools[i].enabled && (isShortToken || gmPools[i].long == _token)) {
                uint256 tokenInvested = poolTokenBalance(i, _token);
                totalInv += tokenInvested;
                ponderatedApr += tokenInvested * gmPools[i].gmApr;
            }
        }

        return (ponderatedApr / totalInv).mul(compoundPctg).mul(10000 - gmWethMintFee).mul(investedPctg).div(10 ** 12);
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

    function getExpectedNFTAnnualYield() external view returns (uint256 totalYield) {
        for (uint256 i = 0; i < gmPools.length; i++) {
            if (gmPools[i].enabled) {
                totalYield += usdInPool(i).mul(gmPools[i].gmApr).mul(rewardSplit.NftPercentage).div(100000000);
            }
        }
    }

    /*---------------------------Methods: token handling--------------------------------*/

    //Sets manually the desired long weight for a GM pool
    function setLongWeight(uint256 _pool, uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 10000 && _percent > 0, 'MuchoProtocolGmxv2.setLongWeight: not in range');
        require(manualModeWeights, 'MuchoProtocolGmxv2.setLongWeight: automatic mode');
        gmPools[i].longWeight = _percent;
    }

    function updateGmWeights() external onlyTraderOrAdmin {
        _updateGmWeights();
    }

    //Updates desired weights from GMX in automatic mode:
    function _updateGmWeights() internal {
        if (manualModeWeights) {
            return;
        }

        //Update weights
        for (uint256 i = 0; i < gmPools.length; i++) {
            if (gmPools[i].enabled) {
                gmPools[i].longWeight = (10000 * longs[i]) / (longs[i] + shorts[i]);
            }
        }
    }

    /*----------------------------Public VIEWS to get the token amounts------------------------------*/

    function getDepositFee(address _token, uint256 _amount) public view returns (uint256) {
        uint256 totalDepFee = getGmDepositFee(_token, _amount).add(getGmWithdrawalFee(_token, _amount)).add(additionalDepositFee);
        return _amount.mul(totalDepFee).div(10000);
    }

    function getWithdrawalFee(address _token, uint256 _amount) public view returns (uint256) {
        return _amount.mul(additionalWithdrawFee).div(10000);
    }

    function getGmDepositFee(address _token, uint256 _amount) public view returns (uint256 fee) {
        bool isShortToken = (address(shortToken) == _token);
        //Get the worst case of positive impact + negative impact fee
        for (uint256 i = 0; i < gmPools.length; i++) {
            if (gmPools[i].enabled && (isShortToken || gmPools[i].long == _token)) {
                uint256 poolFee = IGmxDataStore(IGmPool(gmPools[i].gmAddress).dataStore()).getUint(gmPools[i].positiveSwapFee) +
                    IGmxDataStore(IGmPool(gmPools[i].gmAddress).dataStore()).getUint(gmPools[i].negativeSwapFee);
                if (poolFee > fee) {
                    fee = poolFee;
                }
            }
        }
    }

    function getGmWithdrawalFee(address _token, uint256 _amount) public view returns (uint256) {
        return 0;
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

    //Total USD value (invested + not)
    function getTotalUSD() external view returns (uint256) {
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
    function getTotalUSDBacked() external view returns (uint256) {
        uint256 totalUsd = 0;

        //Add not invested part (ERC20 tokens balance of the contract)
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            totalUsd = totalUsd.add(getTokenUSDNotInvested(tokenList.at(i)));
        }

        //Add GM backing
        for (uint256 i = 0; i < gmPools.length; i++) {
            if (gmPools[i].enabled) {
                totalUsd = totalUsd.add(gmBalanceToUsd(i));
            }
        }

        return totalUsd;
    }

    /*---------------------------INTERNAL Methods--------------------------------*/

    //Get total USD invested from pools where a token is present in short or long:
    function usdFromPoolsWhereTokenIs(address _token) internal {
        bool isShortToken = (address(shortToken) == _token);

        //Calc usd investment per pool and total usd investment, to ponderate:
        uint256[] usdInvested = new uint256[](gmPools.length);
        uint256 totalUsdInvested;
        for (uint256 i = 0; i < gmPools.length; i++) {
            if (gmPools[i].enabled && (isShortToken || gmPools[i].long == _token)) {
                usdInvested[i] = gmPoolInvestedUsd(i);
                totalUsdInvested += usdInvested[i];
            }
        }

        return (totalUsdInvested, usdInvested);
    }

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
        //Only can do delta neutral if all tokens are present
        for (uint256 i = 0; i < tokenUsd.length; i++) {
            if (tokenUsd[i] == 0) {
                return;
            }
        }

        _updateGmWeights();

        TokenAmount[] longUsdAmounts;
        uint256 shortUsdAmount = getShortUSDStaked();

        //List of enabled pools + longAmounts:
        GmPool[] enabledPools;
        for (uint256 i = 0; i < gmPools.length; i++) {
            if (gmPools[i].enabled) {
                enabledPools.push(gmPools[i]);
                longUsdAmounts.push(getTokenUSDStaked(gmPools[i].long));
            }
        }

        //Ask for investments
        (uint256[] longs, uint256[] shorts) = muchoGmxV2Logic.getTokensInvestment(gmPools, longUsdAmounts, shortUsdAmount, minNotInvested);

        //Apply:
        uint256 iEnabledPool = 0;
        for (uint256 i = 0; i < gmPools.length; i++) {
            if (gmPools[i].enabled) {
                //Buy GM with long if needed
                if (longs[iEnabledPool] > (getTokenUSDInvested(gmPools[i].long) * (10000 + minBasisPointsMove)) / 10000) {
                    uint256 usdToInvest = longs[iEnabledPool] - getTokenUSDInvested(gmPools[i].long);
                    uint256 tokenToInvest = usdToToken(usdToInvest, gmPools[i].long);
                    convertTokenToGm(gmPools[i].long, i, tokenToInvest);
                }
                //Sell GM to long if needed
                else if (longs[iEnabledPool] < (getTokenUSDInvested(gmPools[i].long) * (10000 - minBasisPointsMove)) / 10000) {
                    uint256 usdToUninvest = getTokenUSDInvested(gmPools[i].long) - longs[iEnabledPool];
                    uint256 tokenToUninvest = usdToToken(usdToUninvest, gmPools[i].long);
                    convertGmToToken(gmPools[i].long, i, tokenToUninvest);
                }

                //Buy GM with short if needed
                if (shorts[iEnabledPool] + longs[iEnabledPool] > (gmBalanceToUsd(i) * (10000 + minBasisPointsMove)) / 10000) {
                    uint256 usdToInvest = shorts[iEnabledPool] + longs[iEnabledPool] - gmBalanceToUsd(i);
                    uint256 tokenToInvest = usdToToken(usdToInvest, shortToken);
                    convertTokenToGm(shortToken, i, tokenToInvest);
                }
                //Sell GM to short if needed
                else if (shorts[iEnabledPool] + longs[iEnabledPool] < (gmBalanceToUsd(i) * (10000 - minBasisPointsMove)) / 10000) {
                    uint256 usdToUninvest = gmBalanceToUsd(i) - shorts[iEnabledPool] - longs[iEnabledPool];
                    uint256 tokenToUninvest = usdToToken(usdToUninvest, shortToken);
                    convertGmToToken(shortToken, i, tokenToUninvest);
                }

                iEnabledPool++;
            }
        }
    }

    //Get WETH rewards and distribute among the vaults and owner
    function cycleRewardsETH() private {
        uint256 wethInit = WETH.balanceOf(address(this));

        //claim weth fees
        gmxRewardRouter.claimFees();
        uint256 rewards = WETH.balanceOf(address(this)).sub(wethInit);

        if (rewards > 0) {
            //console.log("    SOL - WETH init", wethInit);
            //console.log("    SOL - WETH rewards", rewards);
            //console.log("    SOL - NFT percentage", rewardSplit.NftPercentage);
            //console.log("    SOL - Owner percentage", rewardSplit.ownerPercentage);
            //use compoundPercentage to calculate the total amount and swap to GLP
            uint256 compoundAmount = rewards.mul(10000 - rewardSplit.NftPercentage - rewardSplit.ownerPercentage).div(10000);
            //console.log("    SOL - Compound amount", compoundAmount);
            if (compoundProtocol != this) notInvestedTrySend(address(WETH), compoundAmount, address(compoundProtocol));
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

    //Validates a token
    function validToken(address _token) internal view returns (bool) {
        if (tokenList.contains(_token)) return true;

        return false;
    }

    /*----------------------------Internal token conversion methods------------------------------*/

    function tokenToUsd(address _token, uint256 _amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _amount.mul(priceFeed.getPrice(_token)).div(10 ** (12 + decimals));
    }

    function usdToToken(uint256 _usdAmount, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _usdAmount.mul(10 ** decimals).div(priceFeed.getPrice(_token).div(10 ** 12));
    }

    /*----------------------------GLP mint and token conversion------------------------------*/

    //Burn GM and get token
    function convertGmToToken(address _token, uint256 _poolIndex, uint256 amount) private returns (uint256) {
        //ToDo
        IERC20(gmPools[_poolIndex].gmAddress).safeIncreaseAllowance(gmxRouter, amount);
        exchangeRouter.sendWnt(gmxWithdrawalVault, EXECUTIONFEE_KEEPERS);
        exchangeRouter.sendTokens(_token, gmxWithdrawalVault, amount);
        DepositUtils.CreateWithdrawalParams params = DepositUtils.CreateWithdrawalParams({
            receiver: address(this),
            callbackContract: 0x0,
            uiFeeReceiver: 0x0,
            market: gmPools[_poolIndex].gmAddress,
            longTokenSwapPath: [],
            shortTokenSwapPath: [],
            minLongTokenAmount: 0,
            minShortTokenAmount: 0,
            shouldUnwrapNativeToken: false,
            executionFee: EXECUTIONFEE_KEEPERS,
            callbackGasLimit: 0
        });
        exchangeRouter.createWithdrawal(params);
    }

    //Mint GM from token
    function convertTokenToGm(address _token, uint256 _poolIndex, uint256 amount) private returns (uint256) {
        IERC20(_token).safeIncreaseAllowance(gmxRouter, amount);
        exchangeRouter.sendWnt(gmxDepositVault, EXECUTIONFEE_KEEPERS);
        exchangeRouter.sendTokens(_token, gmxDepositVault, amount);
        DepositUtils.CreateDepositParams params = DepositUtils.CreateDepositParams({
            receiver: address(this),
            callbackContract: 0x0,
            uiFeeReceiver: 0x0,
            market: gmPools[_poolIndex].gmAddress,
            initialLongToken: gmPools[i].long,
            initialShortToken: shortToken,
            longTokenSwapPath: [],
            shortTokenSwapPath: [],
            minMarketTokens: 0,
            shouldUnwrapNativeToken: false,
            executionFee: EXECUTIONFEE_KEEPERS,
            callbackGasLimit: 0
        });
        exchangeRouter.createDeposit(params);
    }
}
