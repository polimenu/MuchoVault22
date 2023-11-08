/*
UNDER CONSTRUCTION!!!
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;


import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../../interfaces/IMuchoProtocol.sol";
import "../../interfaces/IOneInchRouter.sol";
import "../../interfaces/IMuchoRewardRouter.sol";
import "../../interfaces/MUX/IMuxPriceFeed.sol";
import "../../interfaces/MUX/IMlpRewardRouter.sol";
import "../../interfaces/MUX/IMuxOrderBook.sol";
import "../../interfaces/MUX/IMlpVester.sol";
import "../MuchoRoles.sol";

contract MuchoProtocolMUX is IMuchoProtocol, MuchoRoles, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint64;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;


    function protocolName() public pure returns (string memory) {
        return "MUX.network delta-neutral strategy";
    }

    function protocolDescription() public pure returns (string memory) {
        return "Performs a delta neutral strategy against MUXLP yield from MUX network protocol";
    }


    function init() external onlyAdmin{
       /* glpApr = 1800;
        glpWethMintFee = 25;
        compoundProtocol = IMuchoProtocol(address(this));
        rewardSplit = RewardSplit({NftPercentage: 1000, ownerPercentage: 2000});
        grantRole(CONTRACT_OWNER, 0x7832fAb4F1d23754F89F30e5319146D16789c088);
        tokenList.add(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        tokenToSecondaryTokens[0xaf88d065e77c8cC2239327C5EDb3A432268e5831].add(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
        tokenToSecondaryTokens[0xaf88d065e77c8cC2239327C5EDb3A432268e5831].add(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
        tokenToSecondaryTokens[0xaf88d065e77c8cC2239327C5EDb3A432268e5831].add(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
        tokenToSecondaryTokens[0xaf88d065e77c8cC2239327C5EDb3A432268e5831].add(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
        tokenList.add(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        tokenToSecondaryTokens[0x82aF49447D8a07e3bd95BD0d56f35241523fBab1].add(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);
        tokenToSecondaryTokens[0x82aF49447D8a07e3bd95BD0d56f35241523fBab1].add(0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0);
        tokenList.add(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);*/
    }


    /*---------------------------Variables--------------------------------*/
    //Last time rewards collected and values refreshed
    uint256 public lastUpdate = block.timestamp;

    //Desired weight (same MLP has) for every token
    mapping(address => uint256) public mlpWeight;

    //Supported staked investment
    mapping(address => uint256) public amountStaked;

    //Client APRs for each token
    mapping(address => uint256) public aprToken;
    

    /*---------------------------Parameters--------------------------------*/

    //Minimum claimable MLP to claim
    uint256 public minVMLPtoClaim = 10 * 10**18;
    function setMinVMLPtoClaim(uint256 _min) external onlyTraderOrAdmin{ minVMLPtoClaim = _min; }

    //Pool for 1inch to move MCB to WETH
    uint256[] public poolsMCBtoWETH = [1260341638500800461528502024617555594674146880755];
    function updatePoolsMCBtoWETH(uint256[] _pools) external onlyTraderOrAdmin{ poolsMCBtoWETH = _pools; }

    //MLP Yield APR from MUX --> used to estimate our APR
    uint256 public mlpApr;
    function updateMlpApr(uint256 _apr) external onlyTraderOrAdmin{
        mlpApr = _apr;
        _updateAprs();
    }

    //MLP mint fee for weth --> used to calculate final APR, since is a compound cost
    uint256 public mlpWethMintFee;
    function updateMlpWethMintFee(uint256 _fee) external onlyTraderOrAdmin{
        mlpWethMintFee = _fee;
        _updateAprs();
    }

    //List of allowed tokens
    EnumerableSet.AddressSet tokenList;
    mapping(address => uint256) public tokenToAssetId;
    mapping(uint256 => address) public assetIdToToken;
    function addToken(address _token, uint256 _assetId) external onlyAdmin {
        tokenList.add(_token);
        tokenToAssetId[_token] = _assetId;
        assetIdToToken[_assetId] = _token;
    }
    function getTokens() external view returns(address[] memory){
        address[] memory tk = new address[](tokenList.length());
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            tk[i] = tokenList.at(i);
        }
        return tk;
    }

    //Relation between a token and secondary for weight computing (eg. USDT and DAI can be secondary for USDC)
    mapping(address => EnumerableSet.AddressSet) tokenToSecondaryTokens;
    function addSecondaryToken(address _mainToken, address _secondary, uint256 _assetId) external onlyAdmin { 
        tokenToSecondaryTokens[_mainToken].add(_secondary);
        tokenToAssetId[_secondary] = _assetId;
        assetIdToToken[_assetId] = _secondary;
    }
    function removeSecondaryToken(address _mainToken, address _secondary) external onlyAdmin { 
        tokenToSecondaryTokens[_mainToken].remove(_secondary);    
    }
    function getSecondaryTokens(address _mainToken) external view returns(address[] memory){
        EnumerableSet.AddressSet storage secList = tokenToSecondaryTokens[_mainToken];
        address[] memory tk = new address[](secList.length());
        for (uint256 i = 0; i < secList.length(); i = i.add(1)) {
            tk[i] = secList.at(i);
        }
        return tk;
    }

    //Slippage we use when converting to MLP, to have a security gap with mint fees
    uint256 public slippage = 100;
    function setSlippage(uint256 _slippage) external onlyTraderOrAdmin {
        require(_slippage >= 10 && _slippage <= 1000, "not in range");
        slippage = _slippage;
    }

    //Address where we send the owner profit
    address public earningsAddress = 0x829C145cE54A7f8c9302CD728310fdD6950B3e16;
    function setEarningsAddress(address _earnings) external onlyAdmin {
        require(_earnings != address(0), "not valid");
        earningsAddress = _earnings;
    }

    //Claim MUX, set false to save gas
    bool public claimMux = true;
    function updateClaimMux(bool _new) external onlyTraderOrAdmin {
        claimMux = _new;
    }

     // Safety not-invested margin min and desired (2 decimals)
    uint256 public minNotInvestedPercentage = 250;
    function setMinNotInvestedPercentage(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 9000 && _percent >= 0, "MuchoProtocolMUX: minNotInvestedPercentage not in range");
        minNotInvestedPercentage = _percent;
    }
    uint256 public desiredNotInvestedPercentage = 500;
    function setDesiredNotInvestedPercentage(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 9000 && _percent >= 0, "MuchoProtocolMUX: desiredNotInvestedPercentage not in range");
        desiredNotInvestedPercentage = _percent;
    }

    //If variation against desired weight is less than this, do not move:
    uint256 public minBasisPointsMove = 100;
    function setMinWeightBasisPointsMove(uint256 _percent) external onlyTraderOrAdmin {
        require(_percent < 500 && _percent > 0, "MuchoProtocolMUX: minBasisPointsMove not in range");
        minBasisPointsMove = _percent;
    }

    //How do we split the rewards (percentages for owner and nft holders)
    RewardSplit public rewardSplit;
    function setRewardPercentages(RewardSplit calldata _split) external onlyTraderOrAdmin {
        require(_split.NftPercentage.add(_split.ownerPercentage) <= 10000, "MuchoProtocolMUX: NTF and owner fee are more than 100%");
        rewardSplit = RewardSplit({
            NftPercentage: _split.NftPercentage,
            ownerPercentage: _split.ownerPercentage
        });
        _updateAprs();
    }

     // Additional manual deposit fee
    uint256 public additionalDepositFee = 0;
    function setAdditionalDepositFee(uint256 _fee) external onlyTraderOrAdmin {
        require(_fee < 20, "MuchoProtocolMUX: setAdditionalDepositFee not in range");
        additionalDepositFee = _fee;
    }

     // Additional manual withdraw fee
    uint256 public additionalWithdrawFee = 0;
    function setAdditionalWithdrawFee(uint256 _fee) external onlyTraderOrAdmin {
        require(_fee < 20, "MuchoProtocolMUX: setAdditionalWithdrawFee not in range");
        additionalWithdrawFee = _fee;
    }

    //Protocol where we compound the profits
    IMuchoProtocol public compoundProtocol;
    function setCompoundProtocol(IMuchoProtocol _target) external onlyTraderOrAdmin {
        compoundProtocol = _target;
    }


    /*---------------------------Contracts--------------------------------*/

    //MUX tokens - MUX token
    IERC20 public MUX = IERC20(0x8BB2Ac0DCF1E86550534cEE5E9C8DED4269b679B);
    function updateMUX(address _new) external onlyAdmin {
        MUX = IERC20(_new);
    }

    //MLP
    IERC20 public MLP = IERC20(0x7CbaF5a14D953fF896E5B3312031515c858737C8);
    function updateMLP(address _new) external onlyAdmin {
        MLP = IERC20(_new);
    }

    //Staked MLP
    IERC20 public stMLP = IERC20(0x0a9bbf8299FEd2441009a7Bb44874EE453de8e5D);
    function updatestMLP(address _new) external onlyAdmin {
        stMLP = IERC20(_new);
    }

    //Vested MLP
    IERC20 public vMLP = IERC20(0xBCF8c124975DE6277D8397A3Cad26E2333620226);
    function updatevMLP(address _new) external onlyAdmin {
        vMLP = IERC20(_new);
    }

    //MCB
    IERC20 public MCB = IERC20(0x4e352cF164E64ADCBad318C3a1e222E9EBa4Ce42);
    function updateMCB(address _new) external onlyAdmin {
        MCB = IERC20(_new);
    }

    //WETH for the rewards
    IERC20 public WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    function updateWETH(address _new) external onlyAdmin {
        WETH = IERC20(_new);
    }

    //Interfaces to interact with MUX protocol and other externals:

    //One inch router
    IOneInchRouter public oneInchAggregationRouter = IOneInchRouter(0x1111111254eeb25477b68fb85ed929f73a960582);
    function setOneInchAggregationRouter(IOneInchRouter _router) external onlyAdmin{ oneInchAggregationRouter = _router; }

    //IMLPRewardRouter
    IMlpRewardRouter public mlpRewardRouter = IMlpRewardRouter(0xaf9C4F6A0ceB02d4217Ff73f3C95BbC8c7320ceE);
    function setMlpRewardRouter(IMlpRewardRouter _new) external onlyAdmin {
        mlpRewardRouter = _new;
    }

    //IMLPVester
    IMlpVester public mlpVester = IMlpVester(0xBCF8c124975DE6277D8397A3Cad26E2333620226);
    function setMlpVester(IMlpVester _new) external onlyAdmin {
        mlpVester = _new;
    }

    //MUX Order Book
    IMuxOrderBook public muxOrderBook = IMuxOrderBook(0xa19fd5ab6c8dcffa2a295f78a5bb4ac543aaf5e3);
    function setMuxOrderBook(IMuxOrderBook _new) external onlyAdmin {
        muxOrderBook = _new;
    }

    //MLP Reward Tracker
    address public mlpRewardTracker = 0x290450cDea757c68E4Fe6032ff3886D204292914;
    function setMlpRewardTracker(address _new) external onlyAdmin {
        mlpRewardTracker = _new;
    }


    //Own interfaces:

    //MuchoRewardRouter Interaction for NFT Holders
    IMuchoRewardRouter public muchoRewardRouter = IMuchoRewardRouter(0x570C2857CC624077070F7Bb1F10929aad658dA37);
    function setMuchoRewardRouter(address _contract) external onlyAdmin {
        muchoRewardRouter = IMuchoRewardRouter(_contract);
    }

    //MUX Price feed
    IMuxPriceFeed public priceFeed = IMuxPriceFeed(0x846ecf0462981CC0f2674f14be6Da2056Fc16bDA);
    function setPriceFeed(IMuxPriceFeed _feed) external onlyAdmin {
        priceFeed = _feed;
    }


    /*---------------------------Methods: trading interface--------------------------------*/

    //Updates weights, token investment, refreshes amounts and updates aprs:
    function refreshInvestment() external onlyOwnerTraderOrAdmin {
        //console.log("    SOL ***refreshInvestment function***");
        //updateStakedWithApr();
        updateTokensInvestment();
        _MCBtoMLP();
        _stakeMLP();
        _updateAprs();
    }

    //Cycles the rewards from MLP staking and compounds
    function cycleRewards() external onlyOwnerTraderOrAdmin {
        uint256 wethInit = WETH.balanceOf(address(this));

        //claim all fees
        mlpRewardRouter.claimAll();

        //weth rewards: distribute and compound
        uint256 wethRewards = WETH.balanceOf(address(this)).sub(wethInit);
        if(wethRewards > 0){
            //use compoundPercentage to calculate the total amount and swap to MLP
            uint256 compoundAmount = wethRewards.mul(10000 - rewardSplit.NftPercentage - rewardSplit.ownerPercentage).div(10000);
            //console.log("    SOL - Compound amount", compoundAmount);
            if (compoundProtocol == this) {
                swaptoMLP(compoundAmount, address(WETH));
            } else {
                notInvestedTrySend(address(WETH), compoundAmount, address(compoundProtocol));
            }

            //use stakersPercentage to calculate the amount for rewarding stakers
            uint256 stakersAmount = wethRewards.mul(rewardSplit.NftPercentage).div(10000);
            WETH.safeIncreaseAllowance(address(muchoRewardRouter), stakersAmount);
            muchoRewardRouter.depositRewards(address(WETH), stakersAmount);

            //send the rest to earnings
            uint256 earningsAmount = wethRewards.sub(compoundAmount).sub(stakersAmount);
            if(earningsAmount > 0)
                WETH.safeTransfer(earningsAddress, earningsAmount);
            
        }

        //mux rewards
        if(claimMux){
            uint256 muxAmount = MUX.balanceOf(address(this));
            if(muxAmount > 0){
                MUX.safeIncreaseAllowance(address(mlpVester), muxAmount);
                mlpRewardRouter.depositToMlpVester(muxAmount);
            }
        }

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
        require(_amount <= getTokenInvested(_token), "Cannot withdraw more than invested");
        
        //Total MLP to unstake
        uint256 mlpOut = tokenToMlp(_token, _amount.mul(100000 + slippage).div(100000));
        swapMLPto(mlpOut, _token, _amount);

        amountStaked[_token] = amountStaked[_token].sub(_amount);
        IERC20(_token).safeTransfer(_target, _amount);
        emit WithdrawnInvested(_token, _target, _amount, getTokenStaked(_token));
        _updateAprs();
    }

    //Notification from the HUB of a deposit
    function deposit(address _token, uint256 _amount) external onlyOwner nonReentrant {
        require(validToken(_token), "MuchoProtocolMUX.deposit: token not supported");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 amountAfterFees = _amount.sub(getDepositFee(_token, _amount));
        amountStaked[_token] = amountStaked[_token].add(amountAfterFees);
        emit DepositNotified(msg.sender, _token, _amount, amountAfterFees, getTokenStaked(_token));
        
        _updateAprs();
    }

    //Expected APR with current investment
    function getExpectedAPR(address _token, uint256 _additionalAmount) external view returns(uint256){
        return _getExpectedAPR(_token, _additionalAmount);
    }

    function _getExpectedAPR(address _token, uint256 _additionalAmount) internal view returns(uint256){
        //console.log("    SOL - getExpectedAPR", _token, _additionalAmount);
        uint256 sta = amountStaked[_token];
        uint256 notInv = getTokenNotInvested(_token);
        //console.log("    SOL - getExpectedAPR staked notInvested", sta, notInv);

        if(sta < notInv || sta.add(_additionalAmount) == 0)
            return 0;

        uint256 investedPctg = sta.sub(notInv).mul(10000).div(sta.add(_additionalAmount));
        uint256 compoundPctg = 10000 - rewardSplit.NftPercentage - rewardSplit.ownerPercentage;

        return mlpApr.mul(compoundPctg).mul(10000 - mlpWethMintFee).mul(investedPctg).div(10**12);
    }

    function updateAprs() external onlyTraderOrAdmin{
        _updateAprs();
    }

    function _updateAprs() internal{
        updateStakedWithApr();
        for (uint i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);
            aprToken[token] = _getExpectedAPR(token, 0);
        }
    }

    
    function getExpectedNFTAnnualYield() external view returns(uint256){
        return getTotalInvestedUSD().mul(mlpApr).mul(rewardSplit.NftPercentage).div(100000000);
    }


    /*---------------------------Methods: token handling--------------------------------*/

    function convertToMLP(address _token) external onlyTraderOrAdmin  {
        swaptoMLP(IERC20(_token).balanceOf(address(this)), _token);
    }

    //Sets manually the desired weight for a vault
    function setWeight(address _token, uint256 _percent) external onlyTraderOrAdmin {
        _setWeight(_token, _percent);
    }
    function _setWeight(address _token, uint256 _percent) internal {
        require(_percent < 9000 && _percent > 0, "MuchoProtocolMUX.setWeight: not in range");
        mlpWeight[_token] = _percent;
    }
    
    struct Weight{
        address token;
        uint256 weight;
    }
    function setWeights(Weight[] calldata weights) external onlyTraderOrAdmin{
        for(uint i = 0; i < weights.length; i++){
            _setWeight(weights[i].token, weights[i].weight);
        }
    }

    /*----------------------------Public VIEWS to get the token amounts------------------------------*/

    function getDepositFee(address _token, uint256 _amount) public view returns(uint256){
        uint256 totalDepFee = getMlpDepositFee(_token, _amount).add(getMlpWithdrawalFee(_token, _amount)).add(additionalDepositFee);
        return _amount.mul(totalDepFee).div(10000);
    }

    function getWithdrawalFee(address _token, uint256 _amount) public view returns(uint256){
        return _amount.mul(additionalWithdrawFee).div(10000);
    }
    
    function getMlpDepositFee(address _token, uint256 _amount) public view returns(uint256){
        //ToDo
        return -1;
    }

    function getMlpWithdrawalFee(address _token, uint256 _amount) public view returns(uint256){
        //ToDo
        return -1;
    }

    //Amount of token that is invested
    function getTokenInvested(address _token) public view returns (uint256) {
        //console.log("   SOL - getTokenInvested", _token);
        uint256 notInv = getTokenNotInvested(_token);
        uint256 sta = getTokenStaked(_token);
        if(sta < notInv)
            return 0;
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
        uint256 timeDiff = block.timestamp.sub(lastUpdate);
        uint256 earn = amountStaked[_token].mul(aprToken[_token]).mul(timeDiff).div(365 days).div(10000);
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

    //Actual weight for a token vault
    function getTokenWeight(address _token) external view returns (uint256) {
        //console.log("   SOL - getTokenWeight", _token);
        uint256 totUsd = getTotalInvestedUSD();
        if(totUsd == 0)
            return 0;

        return getTokenUSDInvested(_token).mul(10000).div(totUsd);
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
    function getTotalUSDWithTokensUsd() public view returns (uint256, uint256[] memory, uint256[] memory){
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
    function getTotalUSDBacked() external view returns(uint256){
        uint256 totalUsd = 0;

        //Add not invested part (ERC20 tokens balance of the contract)
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            totalUsd = totalUsd.add(getTokenUSDNotInvested(tokenList.at(i)));
        }

        //Add MLP backing
        totalUsd = totalUsd.add(mlpToUsd(getMLPBalance()));

        return totalUsd;
    }

    //Gets the MLP balance of the contract
    function getMLPBalance() public view returns(uint256){
        return stMLP.balanceOf(address(this));
    }
    

    /*---------------------------INTERNAL Methods--------------------------------*/

    //Adds apr to staked value
    function updateStakedWithApr() internal{
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

        //Only can do delta neutral if all tokens are present
        if(tokenUsd[0] == 0 || tokenUsd[1] == 0 || tokenUsd[2] == 0){
            return;
        }

        (address minTokenByWeight, uint256 minTokenUsd) = getMinTokenByWeight(totalUsd, tokenUsd);

        //Calculate and do move for the minimum weight token
        doMinTokenWeightMove(minTokenByWeight);

        //Calc new total USD
        uint256 newTotalInvestedUsd = minTokenUsd
            .mul(10000 - desiredNotInvestedPercentage)
            .div(mlpWeight[minTokenByWeight]);

        //Calculate move for every token different from the main one:
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            address token = tokenList.at(i);

            if (token != minTokenByWeight) {
                doNotMinTokenMove(token, tokenUsd[i], tokenInvestedUsd[i], newTotalInvestedUsd.mul(mlpWeight[token]).div(10000) );
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
            if (mlpWeight[token] > _tokenUsd[i].mul(10000).div(_totalUsd)) {
                uint diff = _totalUsd
                    .mul(mlpWeight[token])
                    .div(_tokenUsd[i])
                    .sub(10000); 
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
        if(notInvestedBalance > totalBalance) //Do not use more than total staked for clients
            notInvestedBalance = totalBalance;
        uint256 notInvestedBP = notInvestedBalance.mul(10000).div(totalBalance);

        //Invested less than desired:
        if (notInvestedBP > desiredNotInvestedPercentage && notInvestedBP.sub(desiredNotInvestedPercentage) > minBasisPointsMove) {
            uint256 amountToMove = notInvestedBalance.sub(
                desiredNotInvestedPercentage.mul(totalBalance).div(10000)
            );
            swaptoMLP(amountToMove, _minTokenByWeight);
        }
        //Invested more than desired:
        else if (notInvestedBP < minNotInvestedPercentage) {
            uint256 mlpAmount = tokenToMlp(_minTokenByWeight, desiredNotInvestedPercentage.mul(totalBalance).div(10000).sub(notInvestedBalance) );
            swapMLPto(mlpAmount, _minTokenByWeight, 0);
        }
    }

    //Moves a token which is not the min
    function doNotMinTokenMove(address _token, uint256 _totalTokenUSD, uint256 _currentUSDInvested, uint256 _newUSDInvested) internal {
        //Invested less than desired:
        if (_newUSDInvested > _currentUSDInvested && _newUSDInvested.sub(_currentUSDInvested).mul(10000).div(_totalTokenUSD) > minBasisPointsMove) {
            uint256 usdToMove = _newUSDInvested.sub(_currentUSDInvested);
            uint256 amountToMove = usdToToken(usdToMove, _token);
            swaptoMLP(amountToMove, _token);
        }

        //Invested more than desired:
        else if (_newUSDInvested < _currentUSDInvested && _currentUSDInvested.sub(_newUSDInvested).mul(10000).div(_currentUSDInvested) > minBasisPointsMove) {
            uint256 mlpAmount = usdToMlp(_currentUSDInvested.sub(_newUSDInvested));
            swapMLPto(mlpAmount, _token, 0);
        }
    }

    //Validates a token
    function validToken(address _token) internal view returns (bool) {
        if (tokenList.contains(_token)) return true;

        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            if (tokenToSecondaryTokens[tokenList.at(i)].contains(_token))
                return true;
        }
        return false;
    }


    /*----------------------------Internal token conversion methods------------------------------*/

    function tokenToMlp(address _token, uint256 _amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        uint8 mlpDecimals = IERC20Metadata(address(stMLP)).decimals();

        return
            _amount
                .mul(priceFeed.getPrice(_token))
                .div(priceFeed.getMLPprice())
                .mul(10 ** mlpDecimals)
                .div(10 ** (decimals + 18));
    }

    function mlpToToken(uint256 _amountMlp, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        uint8 mlpDecimals = IERC20Metadata(address(stMLP)).decimals();

        return
            _amountMlp
                .mul(priceFeed.getMLPprice())
                .mul(10 ** (decimals + 18))
                .div(priceFeed.getPrice(_token))
                .div(10 ** mlpDecimals);
    }

    function tokenToUsd(address _token, uint256 _amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _amount
                    .mul(priceFeed.getPrice(_token))
                    .div(10 ** (12 + decimals));
    }

    function usdToToken(uint256 _usdAmount, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _usdAmount
                    .mul(10 ** decimals)
                    .div(priceFeed.getPrice(_token).div(10**12));
    }

    function usdToMlp(uint256 _usdAmount) internal view returns (uint256) {
        uint8 mlpDecimals = IERC20Metadata(address(stMLP)).decimals();
        return _usdAmount
                    .mul(10 ** mlpDecimals)
                    .div(10 ** 6)
                    .div(priceFeed.getMLPprice());
    }

    function mlpToUsd(uint256 _mlpAmount) internal view returns (uint256) {
        uint8 mlpDecimals = IERC20Metadata(address(stMLP)).decimals();

        return _mlpAmount
                    .mul(priceFeed.getMLPprice())
                    .mul(10 ** 6)
                    .div(10 ** mlpDecimals);
    }



    /*----------------------------MLP mint and token conversion------------------------------*/

    //ToDo!!!
    function swapMLPto( uint256 _amountMlp, address token, uint256 min_receive) private returns (uint256) {
        /*if(_amountMlp > 0){
            uint256 mlpBal = stMLP.balanceOf(address(this));
            if(_amountMlp > mlpBal)
                _amountMlp = mlpBal;

            return glpRouter.unstakeAndRedeemGlp(token, _amountMlp, min_receive, address(this));
        }
        return 0;*/
    }

    //Mint MLP from token
    function swaptoMLP(uint256 _amount, address token) private {
        if(_amount > 0){
            uint256 bal = IERC20(token).balanceOf(address(this));
            if(_amount > bal)
                _amount = bal;

            IERC20(token).safeIncreaseAllowance(address(muxOrderBook), _amount);
            muxOrderBook.placeLiquidityOrder(tokenToAssetId[token], _amount, true);
        }
    }

    //Stake MLP if there is pending
    function stakeMLP() external onlyTraderOrAdmin{
        _stakeMLP();
    }
    function _stakeMLP() internal{
        uint256 amount = IERC20(MLP).balanceOf(address(this));
        if(amount > 0){
            IERC20(MLP).safeIncreaseAllowance(mlpRewardTracker, amount);
            mlpRewardRouter.stakeMlp(amount);
        }
    }

    //Convert MCB obtained into MLP to do autocompounding
    function mcbToMlp() external onlyTraderOrAdmin{
        _MCBtoMLP();
    }
    function _MCBtoMLP() internal{
        //Claim MCB
        if(vMLP.claimable(address(this)) > minVMLPtoClaim){
            mlpVester.claim();
        }

        //Swap to WETH
        uint256 amountMCB = MCB.balanceOf(address(this));
        if(amountMCB > 0){
            MCB.safeIncreaseAllowance(address(oneInchAggregationRouter), amountMCB);
            oneInchAggregationRouter.uniswapV3Swap(amountMCB, 0, poolsMCBtoWETH);
        }
    }


    //ToDo - token un MLP is not invested until it is staked!
    //ToDo - unstake and sell MLP
    //ToDo - deposit and withdrawal fee


    /*-------------------------------MUX ORDERBOOK SUPPORT FUNCTIONS-----------------------------------------*/
    struct LiquidityOrder {
        uint64 id;
        address account;
        uint96 rawAmount; // erc20.decimals
        uint8 assetId;
        bool isAdding;
        uint32 placeOrderTime; // 1e0
    }
    function decodeLiquidityOrder(bytes32[3] memory data) internal pure returns (LiquidityOrder memory order) {
        order.id = uint64(bytes8(data[0] << 184));
        order.account = address(bytes20(data[0]));
        order.rawAmount = uint96(bytes12(data[1]));
        order.assetId = uint8(bytes1(data[1] << 96));
        uint8 flags = uint8(bytes1(data[1] << 104));
        order.isAdding = flags > 0;
        order.placeOrderTime = uint32(bytes4(data[1] << 160));
    }

    function getAmountsInPendingMLPOrders() internal view returns(mapping(address => int256) tokenAmount) {
        uint256 numOrders = muxOrderBook.getOrderCount();
        bytes32[3][] memory orders = muxOrderBook.getOrders(0, numOrders);
        for(uint256 i = 0; i < orders.length; i++){
            LiquidityOrder order = decodeLiquidityOrder(orders[i]);
            tokenAmount[assetIdToToken[order.assetId]].add(order.rawAmount);
        }
    }
}
