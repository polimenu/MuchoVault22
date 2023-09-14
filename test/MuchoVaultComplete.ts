import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MuchoHubMock, PriceFeedMock } from "../typechain-types";
import { BigNumber } from "bignumber.js";
import { formatBytes32String } from "ethers/lib/utils";
import { ethers as eth } from "ethers";
import { InvestmentPartStruct } from "../typechain-types/contracts/MuchoHub";
import { RewardSplitStruct } from "../typechain-types/interfaces/IMuchoProtocol";


describe("MuchoVaultCompleteTest", async function () {

  const toBN = (num: Number, dec: Number): eth.BigNumber => {
    BigNumber.config({ EXPONENTIAL_AT: 100 });
    return eth.BigNumber.from(new BigNumber(num.toString() + "E" + dec.toString()).decimalPlaces(0).toString());
  }

  const fromBN = (bn: eth.BigNumber, dec: number): number => {
    return Number(bn) / (10 ** dec);
  }

  async function deployContract(name: string, params: any[] = []) {
    const [admin, trader, user] = await ethers.getSigners();
    const f = await ethers.getContractFactory(name);
    return f.connect(admin).deploy(...params);
  }

  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployMuchoVault() {
    //Deploy ERC20 fakes
    const usdc = await deployContract("USDC");
    const weth = await deployContract("WETH");
    const wbtc = await deployContract("WBTC");
    const usdt = await deployContract("USDT");
    const dai = await deployContract("DAI");

    //Deploy muchoTokens
    const musdc = await deployContract("mUSDC");
    const mweth = await deployContract("mWETH");
    const mwbtc = await deployContract("mWBTC");

    //ToDo - Deploy actual contracts
    const mBadge = await deployContract("MuchoBadgeManagerMock");
    const f = await ethers.getContractFactory("PriceFeedMock");
    const pFeed = await f.deploy(usdc.address, weth.address, wbtc.address);

    //Deploy MuchoVault
    const mVault = await (await ethers.getContractFactory("MuchoVault")).deploy();

    //Set ownerships
    const [admin, trader, user] = await ethers.getSigners();
    await mVault.grantRole(formatBytes32String("0"), admin.address);
    await mVault.grantRole(formatBytes32String("TRADER"), trader.address);

    //Deploy hub
    const {mHub, mGmx} = await deployHub(pFeed, admin, trader, user, mVault.address, usdc, weth, wbtc, usdt, dai);

    //Grant ownership of muchoTokens
    await musdc.transferOwnership(mVault.address);
    await mweth.transferOwnership(mVault.address);
    await mwbtc.transferOwnership(mVault.address);

    //Set mocks as contracts for vault
    await mVault.setPriceFeed(pFeed.address);
    await mVault.setMuchoHub(mHub.address);
    await mVault.setBadgeManager(mBadge.address);

    //Create Vaults:
    await mVault.addVault(usdc.address, musdc.address);
    await mVault.addVault(weth.address, mweth.address);
    await mVault.addVault(wbtc.address, mwbtc.address);

    await mVault.setEarningsAddress(admin.address);

    return {
      mVault, mHub, tk: [
        { t: usdc.address, m: musdc.address },
        { t: weth.address, m: mweth.address },
        { t: wbtc.address, m: mwbtc.address }
      ], pFeed
      , admin, trader, user, mBadge, mGmx
    };
  }

  async function deployHub(pFeed:PriceFeedMock, admin:SignerWithAddress, trader:SignerWithAddress, user:SignerWithAddress, hubOwnerAddress:string,
    usdc:eth.Contract, weth:eth.Contract, wbtc:eth.Contract, usdt:eth.Contract, dai:eth.Contract){
    //Deploy rest of mocks
    const mHub = await (await ethers.getContractFactory("MuchoHub")).deploy();

    const mGmx = await deployMuchoGMX(pFeed, admin, trader, user, mHub.address, usdc, weth, wbtc, usdt, dai);

    //Set ownerships
    const TRADER_ROLE = await mHub.TRADER();
    const ADMIN_ROLE = await mHub.DEFAULT_ADMIN_ROLE();
    const OWNER_ROLE = await mHub.CONTRACT_OWNER();
    await mHub.grantRole(ADMIN_ROLE, admin.address);
    await mHub.grantRole(TRADER_ROLE, trader.address);
    await mHub.grantRole(OWNER_ROLE, hubOwnerAddress);

    //Set mocks as contracts for vault
    expect((await mHub.protocols()).length).equal(0, "Protocol counter > 0 when nobody added one");
    await mHub.addProtocol(mGmx.address);
    expect((await mHub.protocols()).length).equal(1, "Protocol not properly added");
    expect((await mHub.protocols())[0]).equal(mGmx.address, "Protocol not properly added");

    const part:InvestmentPartStruct = {protocol:mGmx.address, percentage:10000}
    await mHub.setDefaultInvestment(usdc.address, [part]);
    await mHub.setDefaultInvestment(weth.address, [part]);
    await mHub.setDefaultInvestment(wbtc.address, [part]);

    return {mHub, mGmx};
  }

  async function deployMuchoGMX(pFeed:PriceFeedMock ,admin:SignerWithAddress, trader:SignerWithAddress, user:SignerWithAddress, protocolOwnerAddress:string,
    usdc:eth.Contract, weth:eth.Contract, wbtc:eth.Contract, usdt:eth.Contract, dai:eth.Contract) {

    //Deploy ERC20 fakes
    const glp = await deployContract("GLP");

    await usdc.mint(user.address, toBN(100000, 6));
    await weth.mint(user.address, toBN(100, 18));
    await wbtc.mint(user.address, toBN(10, 12));
    await usdt.mint(user.address, toBN(100000, 6));
    await dai.mint(user.address, toBN(100000, 6));


    console.log("usdc", usdc.address);
    console.log("weth", weth.address);
    console.log("wbtc", wbtc.address);
    console.log("usdt", usdt.address);
    console.log("dai", dai.address);

    //Deploy rest of mocks
    const glpVault = await (await ethers.getContractFactory("GLPVaultMock")).deploy(glp.address);
    const glpPriceFeed = await (await ethers.getContractFactory("GLPPriceFeedMock")).deploy(usdc.address, weth.address, wbtc.address, glpVault.address, glp.address);
    await glpPriceFeed.addToken(usdt.address, toBN(1, 30));
    await glpPriceFeed.addToken(dai.address, toBN(1, 30));
    await glpVault.setPriceFeed(glpPriceFeed.address);
    const glpRRct = await ethers.getContractFactory("GLPRewardRouterMock");
    const glpRewardRouter = await glpRRct.deploy(glp.address, glpPriceFeed.address, weth.address);
    const glpRouter = await (await ethers.getContractFactory("GLPRouterMock")).deploy(glpVault.address, glpPriceFeed.address, glp.address, usdc.address, weth.address, wbtc.address);
    await glpVault.setRouter(glpRouter.address);

    //Mint glp and erc tokens supporting it
    await glp.mint(glpVault.address, toBN(10e6, 18));
    await usdc.mint(glpVault.address, toBN(5E6, 6));
    await weth.mint(glpVault.address, toBN(3E6/1600, 18));
    await wbtc.mint(glpVault.address, toBN(3E6/30000, 12));

    //Reward router
    const mRewardRouter = await (await ethers.getContractFactory("MuchoRewardRouter")).deploy();
    await mRewardRouter.connect(admin).grantRole(await mRewardRouter.CONTRACT_OWNER(), admin.address);
    await mRewardRouter.connect(admin).setEarningsAddress(admin.address);

    //Deploy main contract
    const mMuchoGMX = await (await ethers.getContractFactory("MuchoProtocolGMX")).deploy();

    //set contracts:
    await mMuchoGMX.updatefsGLP(glp.address);
    expect(await mMuchoGMX.fsGLP()).equal(glp.address);

    await mMuchoGMX.setEarningsAddress(admin.address);
    expect(await mMuchoGMX.earningsAddress()).equal(admin.address);

    await mMuchoGMX.updateRouter(glpRouter.address);
    expect(await mMuchoGMX.glpRouter()).equal(glpRouter.address);

    await mMuchoGMX.updateRewardRouter(glpRewardRouter.address);
    expect(await mMuchoGMX.glpRewardRouter()).equal(glpRewardRouter.address);

    await mMuchoGMX.updateGLPVault(glpVault.address);
    expect(await mMuchoGMX.glpVault()).equal(glpVault.address);

    await mMuchoGMX.updatepoolGLP(glpVault.address);
    expect(await mMuchoGMX.poolGLP()).equal(glpVault.address);

    await mMuchoGMX.setPriceFeed(glpPriceFeed.address);
    expect(await mMuchoGMX.priceFeed()).equal(glpPriceFeed.address);

    await mMuchoGMX.setMuchoRewardRouter(mRewardRouter.address);
    expect(await mMuchoGMX.muchoRewardRouter()).equal(mRewardRouter.address);

    await mMuchoGMX.updateWETH(weth.address);
    expect(await mMuchoGMX.WETH()).equal(weth.address);

    await mMuchoGMX.setCompoundProtocol(mMuchoGMX.address); //autocompound
    expect(await mMuchoGMX.compoundProtocol()).equal(mMuchoGMX.address);

    //Set ownerships
    const TRADER_ROLE = await mMuchoGMX.TRADER();
    const OWNER_ROLE = await mMuchoGMX.CONTRACT_OWNER();
    const ADMIN_ROLE = await mMuchoGMX.DEFAULT_ADMIN_ROLE();
    await mMuchoGMX.grantRole(ADMIN_ROLE, admin.address);
    await mMuchoGMX.grantRole(TRADER_ROLE, trader.address);
    await mMuchoGMX.grantRole(OWNER_ROLE, protocolOwnerAddress);

    //Add tokens
    await mMuchoGMX.addToken(usdc.address);
    await mMuchoGMX.addToken(weth.address);
    await mMuchoGMX.addToken(wbtc.address);
    await mMuchoGMX.addSecondaryToken(usdc.address, usdt.address);
    await mMuchoGMX.addSecondaryToken(usdc.address, dai.address);

    //Set parameters
    const SLIPPAGE = 100;
    await mMuchoGMX.setSlippage(SLIPPAGE);
    expect(await mMuchoGMX.slippage()).equal(SLIPPAGE);

    const MIN_NOTINV_PCTG = 200;
    await mMuchoGMX.setMinNotInvestedPercentage(MIN_NOTINV_PCTG);
    expect(await mMuchoGMX.minNotInvestedPercentage()).equal(MIN_NOTINV_PCTG);

    const DES_NOTINV_PCTG = 300;
    await mMuchoGMX.setDesiredNotInvestedPercentage(DES_NOTINV_PCTG);
    expect(await mMuchoGMX.desiredNotInvestedPercentage()).equal(DES_NOTINV_PCTG);

    const MIN_WEIGHT_MOVE = 150;
    await mMuchoGMX.setMinWeightBasisPointsMove(MIN_WEIGHT_MOVE);
    expect(await mMuchoGMX.minBasisPointsMove()).equal(MIN_WEIGHT_MOVE);

    const CLAIM_ESGMX = false;
    await mMuchoGMX.updateClaimEsGMX(CLAIM_ESGMX);
    expect(await mMuchoGMX.claimEsGmx()).equal(CLAIM_ESGMX);

    const MANUAL_WEIGHTS = false;
    await mMuchoGMX.setManualModeWeights(MANUAL_WEIGHTS);
    expect(await mMuchoGMX.manualModeWeights()).equal(MANUAL_WEIGHTS);

    const OWNER_PERCENTAGE = 2500; const NFT_PERCENTAGE = 1000;
    const rwSplit:RewardSplitStruct = { ownerPercentage: OWNER_PERCENTAGE, NftPercentage: NFT_PERCENTAGE }
    await mMuchoGMX.setRewardPercentages(rwSplit);
    expect((await mMuchoGMX.rewardSplit()).ownerPercentage).equal(OWNER_PERCENTAGE);
    expect((await mMuchoGMX.rewardSplit()).NftPercentage).equal(NFT_PERCENTAGE);



    return mMuchoGMX;
  }


  /*var mVault: MuchoVault;
  var mHub: MuchoHubMock;
  var tk: { t: string, m: string }[];
  var admin: SignerWithAddress;
  var trader: SignerWithAddress;
  var user: SignerWithAddress;
  var pFeed: PriceFeedMock;*/


  /*before(async function () {
    ({ mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault));
  });*/

  describe("Vault creation and setup", async function () {
    it("Should deploy and create 3 vaults", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
    });

    it("Vaults token should fit", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      for (var i = 0; i < tk.length; i++) {
        const v = await mVault.getVaultInfo(i);
        expect(v.depositToken).to.equal(tk[i].t);
        expect(v.muchoToken).to.equal(tk[i].m);
        expect(v.stakable).to.false;
        expect(await mVault.vaultTotalStaked(i)).to.equal(0);
      }
    });

    it("Should fail when duplicating vaults", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      await expect(mVault.addVault(tk[0].t, tk[0].m)).to.be.revertedWith("MuchoVaultV2.addVault: vault for that deposit or mucho token already exists");

      const dummy = await deployContract("mUSDC");
      await expect(mVault.addVault(dummy.address, tk[0].m)).to.be.revertedWith("MuchoVaultV2.addVault: vault for that deposit or mucho token already exists");
      await expect(mVault.addVault(tk[0].t, dummy.address)).to.be.revertedWith("MuchoVaultV2.addVault: vault for that deposit or mucho token already exists");
    });

    it("Should close and open vaults", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      for (var i = 0; i < tk.length; i++) {
        await mVault.setOpenVault(i, false);
        expect((await mVault.getVaultInfo(i)).stakable).to.be.false;
        await mVault.setOpenVault(i, true);
        expect((await mVault.getVaultInfo(i)).stakable).to.be.true;
        await mVault.setOpenVault(i, false);
        expect((await mVault.getVaultInfo(i)).stakable).to.be.false;
      }
    });
  })

  describe("Deposit", async () => {
    it("Should fail when depositing and it's closed", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      await mVault.setOpenVault(0, false);
      await expect(mVault.connect(admin).deposit(0, 1000)).to.be.revertedWith("MuchoVaultV2.deposit: not stakable");
    });

    it("Should fail when amount is 0", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      await mVault.setOpenVault(0, true);
      await expect(mVault.deposit(0, 0)).to.be.revertedWith("MuchoVaultV2.deposit: Insufficent amount");
    });

    it("Should deposit 1000 usdc", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      const AMOUNT = 1000 * 10 ** 6;
      const token = await ethers.getContractAt("ERC20", tk[0].t);
      //console.log("Amount0", AMOUNT);
      await mVault.setOpenVault(0, true);
      await token.transfer(user.address, AMOUNT);
      await token.connect(user).approve(mHub.address, AMOUNT);
      await mVault.connect(user).deposit(0, AMOUNT);
      expect((await mVault.connect(user).vaultTotalStaked(0))).to.equal(AMOUNT);
      expect(await mVault.connect(user).vaultTotalStaked(0)).to.equal(AMOUNT);

      const mtoken = await ethers.getContractAt("MuchoToken", tk[0].m);
      expect(await mtoken.connect(user).balanceOf(user.address)).to.equal(AMOUNT);
    });

    it("Should deposit 300 usdc with 1,5% fee", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      const INITIAL_AMOUNT = 7135 * 10 ** 6;
      const DEPOSIT = 1562 * 10 ** 6;
      const FEE = 0.015;
      const token = await ethers.getContractAt("ERC20", tk[0].t);
      /*console.log("1Amount", AMOUNT);
      console.log("1CURRENT", CURRENT);
      console.log("1CURRENT_HUB", CURRENT_HUB);
      console.log("1DEPOSITED", DEPOSITED);*/
      await mVault.setDepositFee(0, FEE * 10000);
      await mVault.setOpenVault(0, true);
      await token.transfer(user.address, INITIAL_AMOUNT);
      const initBalance = fromBN(await token.balanceOf(user.address), await token.decimals());
      console.log("Init user balance:", initBalance);
      await token.connect(user).approve(mHub.address, DEPOSIT);
      await mVault.connect(user).deposit(0, DEPOSIT);
      expect((await mVault.vaultTotalStaked(0))).to.equal(Math.round(DEPOSIT * (1 - FEE)));
      expect(await mVault.vaultTotalStaked(0)).to.equal(Math.round(DEPOSIT * (1 - FEE)));

      const mtoken = await ethers.getContractAt("MuchoToken", tk[0].m);
      expect(await mtoken.balanceOf(user.address)).to.equal(Math.round(DEPOSIT * (1 - FEE)), "User muchotoken balance after deposit is unexpected");
      expect(await token.balanceOf(user.address)).to.equal(toBN(initBalance, await token.decimals()).sub(DEPOSIT), "User token balance after deposit is unexpected");
    });
  });

  describe("Withdraw", async () => {
    it("Should withdraw 167 usdc", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      const DEPOSITED = 1000 * 10 ** 6;
      const WITHDRAWN = 167 * 10 ** 6;
      const EXPECTED = DEPOSITED - WITHDRAWN;
      const token = await ethers.getContractAt("ERC20", tk[0].t);
      const mtoken = await ethers.getContractAt("MuchoToken", tk[0].m);
      /*console.log("Amount", AMOUNT);
      console.log("CURRENT", CURRENT);
      console.log("DEPOSITED", DEPOSITED);*/
      await mVault.setWithdrawFee(0, 0);
      await mVault.setOpenVault(0, true);
      await token.transfer(user.address, DEPOSITED);
      await token.connect(user).approve(mHub.address, DEPOSITED);
      await mVault.connect(user).deposit(0, DEPOSITED);
      const initBalance = await token.balanceOf(user.address);
      await mVault.connect(user).withdraw(0, WITHDRAWN);
      expect((await mVault.vaultTotalStaked(0))).to.equal(EXPECTED);
      expect(await mVault.vaultTotalStaked(0)).to.equal(EXPECTED);

      expect(await token.balanceOf(user.address)).to.equal(initBalance.add(WITHDRAWN), "Unexpected user balance of token after withdraw");
      expect(await mtoken.balanceOf(user.address)).to.equal(EXPECTED, "Unexpected user balance of muchotoken after withdraw");

      /*console.log("2CURRENT", await mVault.vaultTotalStaked(0));
      console.log("2CURRENT_HUB", await mHub.getTotalStaked(tk[0].t));*/
    });

    it("Should withdraw 135 usdc with 0,45% fee", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      const DEPOSITED = 1000 * 10 ** 6;
      const WITHDRAWN = 135 * 10 ** 6;
      const FEE = 45;
      const token = await ethers.getContractAt("ERC20", tk[0].t);
      const mtoken = await ethers.getContractAt("MuchoToken", tk[0].m);
      /*console.log("Amount", AMOUNT);
      console.log("CURRENT", CURRENT);
      console.log("DEPOSITED", DEPOSITED);*/
      await mVault.setWithdrawFee(0, FEE);
      await mVault.setOpenVault(0, true);
      const initBalance = await token.balanceOf(user.address);
      await token.transfer(user.address, DEPOSITED);
      await token.connect(user).approve(mHub.address, DEPOSITED);
      await mVault.connect(user).deposit(0, DEPOSITED);
      await mVault.connect(user).withdraw(0, WITHDRAWN);
      const EXPECTED = DEPOSITED - WITHDRAWN;
      expect((await mVault.vaultTotalStaked(0))).to.equal(EXPECTED);
      expect(await mVault.vaultTotalStaked(0)).to.equal(EXPECTED);

      const EXPECTED_BALANCE = initBalance.add(WITHDRAWN * (1 - FEE / 10000));
      expect(await token.balanceOf(user.address)).to.equal(EXPECTED_BALANCE);
      expect(await mtoken.balanceOf(user.address)).to.equal(EXPECTED);
    });
  });


  describe("Earn", async () => {

      //Test data: https://docs.google.com/spreadsheets/d/1OBsrnXMI5orVMv7alr9ZSxZ4F0rT6xvfJxqut-F71yY/edit#gid=603145686
    it("Should earn apr from test", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user, mBadge, mGmx } = await loadFixture(deployMuchoVault);
      const APR = 30; const OWNER = 25; const NFT = 10;
      const LAPSE = 180 * 24 * 60 * 60;
      const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
      const glpRR = (await ethers.getContractAt("GLPRewardRouterMock", await mGmx.glpRewardRouter()));
      await glpRR.setApr(APR * 100);
      const rr:RewardSplitStruct = {ownerPercentage: OWNER*100, NftPercentage: NFT*100};
      await mGmx.setRewardPercentages(rr);
      await mVault.setOpenAllVault(true);
      const getToken = async (i:number) => {return await ethers.getContractAt("MuchoToken", tk[i].t);}

      const GLP_DEP = [1500, 0.375, 0.0125];
      const glpVault = await ethers.getContractAt("GLPVaultMock", await mGmx.glpVault());
      for(var i = 0; i < GLP_DEP.length; i++){
        const token = await getToken(i);
        const curBal = fromBN(await token.balanceOf(glpVault.address), await token.decimals());
        if(curBal < GLP_DEP[i]){
          console.log(`Increasing balance in glp vault for token ${i}`);
          await token.mint(glpVault.address, toBN(GLP_DEP[i] - curBal, await token.decimals()));
        }
        else if(curBal > GLP_DEP[i]){
          console.log(`Decreasing balance in glp vault for token ${i}`);
          await token.burn(glpVault.address, toBN(curBal - GLP_DEP[i], await token.decimals()));

        }
      }
      

      const DEPOSITS = [300, 0.1875, 0.0125];
      const PRICES = [1, 1600, 24000];

      for(var i = 0; i < DEPOSITS.length; i++){
        const token = await getToken(i);
        await pFeed.addToken(token.address, toBN(PRICES[i], 18));
        const DEP_BN = toBN(DEPOSITS[i], await token.decimals());
        await token.transfer(user.address, DEP_BN);
        await token.connect(user).approve(mHub.address, DEP_BN);
        await mVault.connect(user).deposit(i, DEP_BN);
      }
      //await mVault.refreshAndUpdateAllVaults();

      /*console.log("APR", APR);
      console.log("DEPOSITED", DEPOSITED);
      console.log("EARN_PER_SEC", EARN_PER_SEC);
      console.log("ONE_YEAR_IN_SECS", ONE_YEAR_IN_SECS);*/

      //console.log("timeBefore", timeBefore);
      const timeDeposited = await time.latest();
      await time.setNextBlockTimestamp(timeDeposited + LAPSE);

      await mVault.refreshAndUpdateAllVaults();

      /*console.log("timeDeposited", timeDeposited);
      console.log("timeAfter", timeAfter);
      console.log("lapse", lapse);*/
      const EXPECTEDS = [327.1864, 0.194297, 0.0127266]
      const TOLERANCE = 0.01;
      for(var i = 0; i < DEPOSITS.length; i++){
        const token = await getToken(i);
        const staked = fromBN(await mVault.connect(user).vaultTotalStaked(i), await token.decimals());
        const EXPECTED = EXPECTEDS[i];
        //console.log("EXPECTED", EXPECTED);
        expect(staked).closeTo(EXPECTED, EXPECTED * TOLERANCE, "Staked value after APR is not correct");
      }
    });

  });

  /*describe("Swap", async () => {

    

    it("Should fail when trying to swap more than 10% of total in destination vault", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      await mVault.setOpenAllVault(true);

      //Transfer tokens to user and approve to be spent by the HUB:
      for (var j = 0; j < tk.length; j++) {
        const ct = await ethers.getContractAt("ERC20", tk[j].t);
        const am = await ct.balanceOf(admin.address);
        await ct.transfer(user.address, am);
        await ct.connect(user).approve(mHub.address, am);
      }

      //console.log("Make destination vault deposit");
      await mVault.connect(user).deposit(1, toBN(1, 18));

      //console.log("Make source vault deposit");
      await mVault.connect(user).deposit(0, toBN(1000, 6));

      await expect(mVault.connect(user).swap(0, toBN(500, 6), 1, toBN(0.5, 18), 0))
        .revertedWith("MuchoVaultV2.swap: cannot swap more than 10% of total source");
    });


    it("Swap with an NFT, using the right swap fee", async function () {
      const SECONDS_PER_DAY = 24 * 3600;

      const { mVault, mHub, tk, pFeed, admin, trader, user, mBadge, mGmx } = await loadFixture(deployMuchoVault);

      //Add user to NFT plan 3 and 4
      await mBadge.addUserToPlan(user.address, 3);
      await mBadge.addUserToPlan(user.address, 4);

      //set Fees
      const FEE_STD = 150, FEE1 = 140, FEE_MIN = 120, FEE_MIN2 = 110, FEE_MIN3 = 75;
      await mVault.setSwapMuchoTokensFee(FEE_STD);
      await mVault.setSwapMuchoTokensFeeForPlan(3, FEE1);
      await mVault.setSwapMuchoTokensFeeForPlan(4, FEE_MIN);

      //set glp mint fees to 0
      const glpVaultAddr = await mGmx.glpVault();
      const glpVaultMock = await ethers.getContractAt("GLPVaultMock", glpVaultAddr);
      await glpVaultMock.setMintFee(0);
      await glpVaultMock.setBurnFee(0);

      //Manual weights to avoid rebalance
      await mGmx.setManualModeWeights(true);
      await mVault.setOpenAllVault(true);

      //Calc total usd to calc weight
      let totalAmoundUSD = 0;
      for (var j = 0; j < tk.length; j++) {
        const ct = await ethers.getContractAt("ERC20", tk[j].t);
        const am = await ct.balanceOf(admin.address);
        const pr = await pFeed.getPrice(ct.address);
        totalAmoundUSD += (fromBN(am, await ct.decimals()) * fromBN(pr, 30));
      };

      //Transfer tokens to user, approve to be spent by the HUB, and deposit them:
      for (var j = 0; j < tk.length; j++) {
        const ct = await ethers.getContractAt("ERC20", tk[j].t);
        const am = await ct.balanceOf(admin.address);
        const pr = await pFeed.getPrice(ct.address);
        const weight = Math.round((fromBN(am, await ct.decimals()) * fromBN(pr, 30)) * 10000 / totalAmoundUSD);
        await mGmx.setWeight(tk[j].t, weight);
        await ct.transfer(user.address, am);
        await ct.connect(user).approve(mHub.address, am);
        await mVault.connect(user).deposit(j, am);
      }


      //Expected exchange:
      const amountSource = 1.26346;
      const vaultSource = 1;
      const vaultDestination = 2;
      const tkSource = await ethers.getContractAt("ERC20", tk[vaultSource].t);
      const tkDestination = await ethers.getContractAt("ERC20", tk[vaultDestination].t);
      const mtkSource = await ethers.getContractAt("ERC20", tk[vaultSource].m);
      const mtkDestination = await ethers.getContractAt("ERC20", tk[vaultDestination].m);
      const PRICE_SOURCE = await pFeed.getPrice(tkSource.address);
      const PRICE_DESTINATION = await pFeed.getPrice(tkDestination.address);
      const DECIMALS_SOURCE = await tkSource.decimals();
      const DECIMALS_DESTINATION = await tkDestination.decimals();
      const bnAmountSource = toBN(amountSource, DECIMALS_SOURCE);

      //Check if uses the NFT minimum fee:
      let expected = (amountSource * (1 - FEE_MIN / 10000)) * fromBN(PRICE_SOURCE, 30) / fromBN(PRICE_DESTINATION, 30);
      let result = await mVault.connect(user).getSwap(vaultSource, bnAmountSource, vaultDestination);
      expect(result).closeTo(toBN(expected, DECIMALS_DESTINATION), 10, "Swap amount is not what expected");

      //console.log("Assert swap performs how expected");
      {
        const initialMSrc = await mtkSource.balanceOf(user.address);
        const initialMDst = await mtkDestination.balanceOf(user.address);
        //console.log("Initial mucho source", initialM0);
        //console.log("Initial mucho dest", initialM1);
        await mVault.connect(user).swap(vaultSource, bnAmountSource, vaultDestination, result, 0);

        const finalMSrc = await mtkSource.balanceOf(user.address);
        const finalMDst = await mtkDestination.balanceOf(user.address);
        //console.log("Final mucho source", finalM0);
        //console.log("Final mucho dest", finalM1);
        expect(initialMSrc.sub(finalMSrc)).equal(bnAmountSource, "Final amount of muchotoken source is not what I expected");
        expect(finalMDst.sub(initialMDst)).equal(result, "Final amount of muchotoken source is not what I expected");
      }


      //Set min fee in another plan the user doesnt have
      await mVault.setSwapMuchoTokensFeeForPlan(2, FEE_MIN2);
      expected = (amountSource * (1 - FEE_MIN / 10000)) * fromBN(PRICE_SOURCE, 30) / fromBN(PRICE_DESTINATION, 30);
      result = await mVault.connect(user).getSwap(vaultSource, toBN(amountSource, DECIMALS_SOURCE), vaultDestination);
      expect(result).closeTo(toBN(expected, DECIMALS_DESTINATION), 10, "Swap amount is not what expected");
      //console.log("Assert swap performs how expected");
      {
        const initialMSrc = await mtkSource.balanceOf(user.address);
        const initialMDst = await mtkDestination.balanceOf(user.address);
        //console.log("Initial mucho source", initialM0);
        //console.log("Initial mucho dest", initialM1);
        await mVault.connect(user).swap(vaultSource, bnAmountSource, vaultDestination, result, 0);

        const finalMSrc = await mtkSource.balanceOf(user.address);
        const finalMDst = await mtkDestination.balanceOf(user.address);
        //console.log("Final mucho source", finalM0);
        //console.log("Final mucho dest", finalM1);
        expect(initialMSrc.sub(finalMSrc)).equal(bnAmountSource, "Final amount of muchotoken source is not what I expected");
        expect(finalMDst.sub(initialMDst)).equal(result, "Final amount of muchotoken source is not what I expected");
      }

      //Set min fee in another plan the user have
      await mVault.setSwapMuchoTokensFeeForPlan(3, FEE_MIN2);
      expected = (amountSource * (1 - FEE_MIN2 / 10000)) * fromBN(PRICE_SOURCE, 30) / fromBN(PRICE_DESTINATION, 30);
      result = await mVault.connect(user).getSwap(vaultSource, toBN(amountSource, DECIMALS_SOURCE), vaultDestination);
      expect(result).closeTo(toBN(expected, DECIMALS_DESTINATION), 2, "Swap amount is not what expected");
      //console.log("Assert swap performs how expected");
      {
        const initialMSrc = await mtkSource.balanceOf(user.address);
        const initialMDst = await mtkDestination.balanceOf(user.address);
        //console.log("Initial mucho source", initialM0);
        //console.log("Initial mucho dest", initialM1);
        await mVault.connect(user).swap(vaultSource, bnAmountSource, vaultDestination, result, 0);

        const finalMSrc = await mtkSource.balanceOf(user.address);
        const finalMDst = await mtkDestination.balanceOf(user.address);
        //console.log("Final mucho source", finalM0);
        //console.log("Final mucho dest", finalM1);
        expect(initialMSrc.sub(finalMSrc)).equal(bnAmountSource, "Final amount of muchotoken source is not what I expected");
        expect(finalMDst.sub(initialMDst)).equal(result, "Final amount of muchotoken source is not what I expected");
      }

      //Set min fee in std
      await mVault.setSwapMuchoTokensFee(FEE_MIN3);
      expected = (amountSource * (1 - FEE_MIN3 / 10000)) * fromBN(PRICE_SOURCE, 30) / fromBN(PRICE_DESTINATION, 30);
      result = await mVault.connect(user).getSwap(vaultSource, toBN(amountSource, DECIMALS_SOURCE), vaultDestination);
      expect(result).closeTo(toBN(expected, DECIMALS_DESTINATION), 10, "Swap amount is not what expected");
      //console.log("Assert swap performs how expected");
      {
        const initialMSrc = await mtkSource.balanceOf(user.address);
        const initialMDst = await mtkDestination.balanceOf(user.address);
        //console.log("Initial mucho source", initialM0);
        //console.log("Initial mucho dest", initialM1);
        await mVault.connect(user).swap(vaultSource, bnAmountSource, vaultDestination, result, 0);

        const finalMSrc = await mtkSource.balanceOf(user.address);
        const finalMDst = await mtkDestination.balanceOf(user.address);
        //console.log("Final mucho source", finalM0);
        //console.log("Final mucho dest", finalM1);
        expect(initialMSrc.sub(finalMSrc)).equal(bnAmountSource, "Final amount of muchotoken source is not what I expected");
        expect(finalMDst.sub(initialMDst)).equal(result, "Final amount of muchotoken source is not what I expected");
      }
    });


  });*/

  describe("Roles", async function () {
    it("Should only work with the right roles", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);

      //ADMIN functions
      const ONLY_ADMIN_REASON = "MuchoRoles: Only for admin";
      await expect(mVault.connect(user).setMuchoHub(admin.address)).revertedWith(ONLY_ADMIN_REASON);
      await expect(mVault.connect(trader).setMuchoHub(admin.address)).revertedWith(ONLY_ADMIN_REASON);

      await expect(mVault.connect(user).setPriceFeed(admin.address)).revertedWith(ONLY_ADMIN_REASON);
      await expect(mVault.connect(trader).setPriceFeed(admin.address)).revertedWith(ONLY_ADMIN_REASON);

      await expect(mVault.connect(user).setBadgeManager(admin.address)).revertedWith(ONLY_ADMIN_REASON);
      await expect(mVault.connect(trader).setBadgeManager(admin.address)).revertedWith(ONLY_ADMIN_REASON);

      await expect(mVault.connect(user).addVault(tk[0].t, tk[0].m)).revertedWith(ONLY_ADMIN_REASON);
      await expect(mVault.connect(trader).addVault(tk[0].t, tk[0].m)).revertedWith(ONLY_ADMIN_REASON);


      //ADMIN or TRADER functions
      const ONLY_TRADER_OR_ADMIN_REASON = "MuchoRoles: Only for trader or admin";

      await expect(mVault.connect(user).setSwapMuchoTokensFee(100)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(mVault.connect(user).setSwapMuchoTokensFeeForPlan(1, 100)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(mVault.connect(user).removeSwapMuchoTokensFeeForPlan(1)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(mVault.connect(user).setDepositFee(1, 100)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(mVault.connect(user).setWithdrawFee(1, 100)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(mVault.connect(user).setOpenVault(1, true)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(mVault.connect(user).setOpenAllVault(true)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(mVault.connect(user).refreshAndUpdateAllVaults()).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
    });
  });
});
