import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { MuchoVaultInterface } from "../typechain-types/contracts/MuchoVault";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MuchoHub, MuchoHubMock, PriceFeedMock } from "../typechain-types";
import { BigNumber } from "bignumber.js";
//import { ethers } from "ethers";
//import { ethers } from "ethers";


describe("MuchoVault", async function () {


  async function deployContract(name: string) {
    const [admin, trader, user] = await ethers.getSigners();
    const f = await ethers.getContractFactory(name);
    return f.connect(admin).deploy();
  }

  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployMuchoVault() {
    //Deploy ERC20 fakes
    const usdc = await deployContract("USDC");
    const weth = await deployContract("WETH");
    const wbtc = await deployContract("WBTC");

    //Deploy muchoTokens
    const musdc = await deployContract("mUSDC");
    const mweth = await deployContract("mWETH");
    const mwbtc = await deployContract("mWBTC");

    //Deploy rest of mocks
    const mBadge = await deployContract("MuchoBadgeManagerMock");
    const mHub = await (await ethers.getContractFactory("MuchoHubMock")).deploy();
    const f = await ethers.getContractFactory("PriceFeedMock");
    const pFeed = await f.deploy(usdc.address, weth.address, wbtc.address);

    //Deploy MuchoVault
    const mVault = await (await ethers.getContractFactory("MuchoVault")).deploy();

    //Grant ownership of muchoTokens
    await musdc.transferOwnership(mVault.address);
    await mweth.transferOwnership(mVault.address);
    await mwbtc.transferOwnership(mVault.address);

    //Set mocks as contracts for vault
    await mVault.setPriceFeed(pFeed.address);
    await mVault.setMuchoHub(mHub.address);
    await mVault.setBadgeManager(mBadge.address);

    return {
      mVault, mHub, tk: [
        { t: usdc.address, m: musdc.address },
        { t: weth.address, m: mweth.address },
        { t: wbtc.address, m: mwbtc.address }
      ], pFeed
    };
  }

  describe("Test vaults", async function () {

    var mVault: MuchoVault;
    var mHub: MuchoHubMock;
    var tk: { t: string, m: string }[];
    var admin: SignerWithAddress;
    var trader: SignerWithAddress;
    var user: SignerWithAddress;
    var pFeed: PriceFeedMock;

    async function createVaults() {
      for (var i = 0; i < tk.length; i++) {
        await mVault.addVault(tk[i].t, tk[i].m);
      }
    }

    before(async function () {
      ({ mVault, mHub, tk, pFeed } = await loadFixture(deployMuchoVault));
      [admin, trader, user] = await ethers.getSigners();
    });

    it("Should create 3 vaults", async function () {
      await createVaults();
    });

    it("Vaults token should fit", async function () {
      for (var i = 0; i < tk.length; i++) {
        const v = await mVault.getVaultInfo(i);
        expect(v.depositToken).to.equal(tk[i].t);
        expect(v.muchoToken).to.equal(tk[i].m);
        expect(v.stakable).to.false;
        expect(v.totalStaked).to.equal(0);
        expect(v.stakedFromDeposits).to.equal(0);
      }
    });

    it("Should fail when duplicating vaults", async function () {
      await expect(mVault.addVault(tk[0].t, tk[0].m)).to.be.revertedWith("MuchoVaultV2.addVault: vault for that deposit or mucho token already exists");

      const dummy = await deployContract("mUSDC");
      await expect(mVault.addVault(dummy.address, tk[0].m)).to.be.revertedWith("MuchoVaultV2.addVault: vault for that deposit or mucho token already exists");
      await expect(mVault.addVault(tk[0].t, dummy.address)).to.be.revertedWith("MuchoVaultV2.addVault: vault for that deposit or mucho token already exists");
    });

    it("Should close and open vaults", async function () {
      for (var i = 0; i < tk.length; i++) {
        await mVault.setOpenVault(i, false);
        /*var z = await mVault.getVaultInfo(i);
        console.log("ZETA:");
        console.log(z);
        console.log(z.stakable);*/
        expect((await mVault.getVaultInfo(i)).stakable).to.be.false;
        await mVault.setOpenVault(i, true);
        expect((await mVault.getVaultInfo(i)).stakable).to.be.true;
        await mVault.setOpenVault(i, false);
        expect((await mVault.getVaultInfo(i)).stakable).to.be.false;
      }
    });

    it("Should fail when depositing and it's closed", async function () {
      /*console.log("ADMIN:");
      console.log(admin.address);
      console.log("Token:");
      console.log(tk[0].t);
      console.log("Balance:");
      const i = ethers.getContractAt("USDC", tk[0].t);
      console.log(await (await i).balanceOf(admin.address));*/

      await mVault.setOpenVault(0, false);

      await expect(mVault.connect(admin).deposit(0, 1000)).to.be.revertedWith("MuchoVaultV2.deposit: not stakable");
    });

    it("Should fail when amount is 0", async function () {
      await mVault.setOpenVault(0, true);
      await expect(mVault.deposit(0, 0)).to.be.revertedWith("MuchoVaultV2.deposit: Insufficent amount");
    });

    it("Should deposit 1000 usdc", async function () {
      const AMOUNT = 1000 * 10 ** 6;
      //console.log("Amount0", AMOUNT);
      await mVault.setOpenVault(0, true);
      await mVault.deposit(0, AMOUNT);
      expect((await mVault.getVaultInfo(0)).totalStaked).to.equal(AMOUNT);
      expect((await mVault.getVaultInfo(0)).stakedFromDeposits).to.equal(AMOUNT);
      expect(await mVault.vaultTotalStaked(0)).to.equal(AMOUNT);

      const token = await ethers.getContractAt("MuchoToken", tk[0].m);
      expect(await token.balanceOf(admin.address)).to.equal(AMOUNT);
    });

    it("Should deposit 300 usdc with 1,5% fee", async function () {
      const CURRENT = Number(await mVault.vaultTotalStaked(0));
      const CURRENT_HUB = Number(await mHub.getTotalStaked(tk[0].t));
      const AMOUNT = 300 * 10 ** 6;
      const FEE = 0.015;
      const DEPOSITED = CURRENT + Math.round(AMOUNT * (1 - FEE));
      /*console.log("1Amount", AMOUNT);
      console.log("1CURRENT", CURRENT);
      console.log("1CURRENT_HUB", CURRENT_HUB);
      console.log("1DEPOSITED", DEPOSITED);*/
      await mVault.setDepositFee(0, FEE * 10000);
      await mVault.setOpenVault(0, true);
      await mVault.deposit(0, AMOUNT);
      expect((await mVault.getVaultInfo(0)).totalStaked).to.equal(DEPOSITED);
      expect((await mVault.getVaultInfo(0)).stakedFromDeposits).to.equal(DEPOSITED);
      expect(await mVault.vaultTotalStaked(0)).to.equal(DEPOSITED);

      const token = await ethers.getContractAt("MuchoToken", tk[0].m);
      expect(await token.balanceOf(admin.address)).to.equal(DEPOSITED);
    });

    it("Should withdraw 167 usdc", async function () {
      const CURRENT = Number(await mVault.vaultTotalStaked(0));
      const AMOUNT = 167 * 10 ** 6;
      const DEPOSITED = CURRENT - AMOUNT;
      /*console.log("Amount", AMOUNT);
      console.log("CURRENT", CURRENT);
      console.log("DEPOSITED", DEPOSITED);*/
      await mVault.setWithdrawFee(0, 0);
      await mVault.setOpenVault(0, true);
      await mVault.withdraw(0, AMOUNT);
      expect((await mVault.getVaultInfo(0)).totalStaked).to.equal(DEPOSITED);
      expect((await mVault.getVaultInfo(0)).stakedFromDeposits).to.equal(DEPOSITED);
      expect(await mVault.vaultTotalStaked(0)).to.equal(DEPOSITED);

      const token = await ethers.getContractAt("MuchoToken", tk[0].m);
      expect(await token.balanceOf(admin.address)).to.equal(DEPOSITED);

      /*console.log("2CURRENT", await mVault.vaultTotalStaked(0));
      console.log("2CURRENT_HUB", await mHub.getTotalStaked(tk[0].t));*/
    });

    it("Should withdraw 135 usdc with 0,45% fee", async function () {
      const CURRENT = Number(await mVault.vaultTotalStaked(0));
      const AMOUNT = 135 * 10 ** 6;
      const FEE = 45;
      const DEPOSITED = CURRENT - AMOUNT;
      /*console.log("Amount", AMOUNT);
      console.log("CURRENT", CURRENT);
      console.log("DEPOSITED", DEPOSITED);*/
      await mVault.setWithdrawFee(0, FEE);
      await mVault.setOpenVault(0, true);
      await mVault.withdraw(0, AMOUNT);
      expect((await mVault.getVaultInfo(0)).totalStaked).to.equal(DEPOSITED);
      expect((await mVault.getVaultInfo(0)).stakedFromDeposits).to.equal(DEPOSITED);
      expect(await mVault.vaultTotalStaked(0)).to.equal(DEPOSITED);

      const token = await ethers.getContractAt("MuchoToken", tk[0].m);
      expect(await token.balanceOf(admin.address)).to.equal(DEPOSITED);
    });


    it("Should earn 200% apr", async function () {
      const APR = 200;
      await mHub.setApr(APR * 100);
      await mVault.refreshAndUpdateAllVaults();
      const timeDeposited = await time.latest();

      const FROMDEP = Number(await mVault.vaultStakedFromDeposits(0));
      const DEPOSITED = Number(await mVault.vaultTotalStaked(0));
      const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
      const EARN_PER_SEC = DEPOSITED * (APR / 100) / ONE_YEAR_IN_SECS;

      console.log("APR", APR);
      console.log("DEPOSITED", DEPOSITED);
      console.log("EARN_PER_SEC", EARN_PER_SEC);
      console.log("ONE_YEAR_IN_SECS", ONE_YEAR_IN_SECS);

      //console.log("timeBefore", timeBefore);
      await time.increaseTo(timeDeposited + ONE_YEAR_IN_SECS);

      await mVault.refreshAndUpdateAllVaults();
      let timeAfter = await time.latest();
      let lapse = timeAfter - timeDeposited;

      console.log("timeDeposited", timeDeposited);
      console.log("timeAfter", timeAfter);
      console.log("lapse", lapse);

      let staked = await mVault.vaultTotalStaked(0);
      const EXPECTED = DEPOSITED + EARN_PER_SEC * lapse;
      console.log("EXPECTED", EXPECTED);
      expect(staked).to.equal(Math.round(EXPECTED));
      expect(await mVault.vaultStakedFromDeposits(0)).to.equal(FROMDEP);
    });

    it("Should earn and measure properly several positive aprs, without deposits in the middle", async function () {
      const aprs = [153, 14, 27, 3141, 10000];
      const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;

      //console.log("ALLA VAMOS----------------------------------------------");

      await mVault.refreshAndUpdateAllVaults();
      await time.increase(ONE_YEAR_IN_SECS);

      for (var i = 0; i < aprs.length; i++) {
        await mHub.setApr(aprs[i] * 100);
        await mVault.refreshAndUpdateAllVaults();
        let staked = await mVault.vaultTotalStaked(0);
        const earnPerSec = staked * aprs[i] / (100 * ONE_YEAR_IN_SECS);
        const timeBefore = await time.latest();
        await time.increase(ONE_YEAR_IN_SECS);
        await mVault.refreshAndUpdateAllVaults();
        const lapse = (await time.latest()) - timeBefore;
        //console.log("Staked", staked);
        let newStaked = await mVault.vaultTotalStaked(0);
        let expected = ethers.BigNumber.from(staked).add(Math.round(earnPerSec * lapse));

        /*console.log("Check staked");
        console.log("apr", aprs[i]);
        console.log("staked", staked);
        console.log("earnPerSec", earnPerSec);
        console.log("lapse", lapse);
        console.log("newStaked", newStaked);
        console.log("expected", expected);*/
        expect(newStaked).to.be.closeTo(expected, expected.div(100000), "APR earned is not what expected to be (${i})");

        //console.log("Check apr");
        let aprsVault = await mVault.getLastPeriodsApr(0);
        //console.log("aprsVault", aprsVault);
        expect(Math.round(aprsVault[0] / 100)).to.equal(aprs[i], `APR calculated by vault is not what is earned (${i})`);

        staked = newStaked;
        /*console.log("Staked", newStaked);
        console.log("Apr", apr);*/
      }

    });


    it("Should earn and measure properly several negative aprs, without deposits in the middle", async function () {
      const aprs = [-153, -14, -27, -3141, -3650000];
      const ONE_DAY_IN_SECS = 24 * 60 * 60;
      const ONE_MONTH_IN_SECS = 30 * ONE_DAY_IN_SECS;
      const ONE_YEAR_IN_SECS = 365 * ONE_DAY_IN_SECS;

      //console.log("ALLA VAMOS----------------------------------------------");

      await mVault.refreshAndUpdateAllVaults();
      await time.increase(ONE_DAY_IN_SECS);

      for (var i = 0; i < aprs.length; i++) {
        await mHub.setApr(aprs[i] * 100);
        await mVault.refreshAndUpdateAllVaults();
        let staked = await mVault.vaultTotalStaked(0);
        const earnPerSec = ethers.BigNumber.from(staked).mul(aprs[i]).div(100).div(ONE_YEAR_IN_SECS);
        const timeBefore = await time.latest();
        await time.increase(ONE_DAY_IN_SECS);
        await mVault.refreshAndUpdateAllVaults();
        const lapse = (await time.latest()) - timeBefore;
        //console.log("Doing APR", aprs[i]);
        //console.log("Staked", staked);
        let newStaked: ethers.BigNumber = await mVault.vaultTotalStaked(0);
        let profit: ethers.BigNumber = ethers.BigNumber.from(earnPerSec).mul(lapse);
        //console.log("profit", profit);
        let expected: ethers.BigNumber = ethers.BigNumber.from(staked).add(profit);
        //console.log("1st expected", expected);
        let realApr = aprs[i];
        if (expected.lt(0)) {
          expected = ethers.BigNumber.from(0);
          realApr = -100 * ONE_YEAR_IN_SECS / lapse;
        }

        /*console.log("Check staked");
        console.log("apr", aprs[i]);
        console.log("staked", staked);
        console.log("earnPerSec", earnPerSec);
        console.log("lapse", lapse);
        console.log("newStaked", newStaked);
        console.log("expected", expected);*/
        expect(newStaked).to.be.closeTo(expected, Math.round(expected / 1000000), "APR earned is not what expected to be (${i})");

        //console.log("Check apr");
        let aprsVault = await mVault.getLastPeriodsApr(0);
        //console.log("aprsVault", aprsVault);
        expect(aprsVault[0] / 100).to.be.closeTo(realApr, Math.abs(realApr / 1000), `APR calculated by vault is not what is earned (${i})`);

        staked = newStaked;
        /*console.log("Staked", newStaked);
        console.log("Apr", apr);*/
      }

    });

    it("Should earn and measure properly several positive and negative aprs, WITH deposits in the middle", async function () {
      const aprs = [153, 34, -27, -3141, -3650000];
      const ONE_DAY_IN_SECS = 24 * 60 * 60;
      const ONE_WEEK_IN_SECS = 7 * ONE_DAY_IN_SECS;
      const ONE_YEAR_IN_SECS = 365 * ONE_DAY_IN_SECS;

      await mVault.setAprUpdatePeriod(3600);

      //console.log("ALLA VAMOS----------------------------------------------");

      await mVault.deposit(0, 1000 * 10 ** 6);
      await mVault.refreshAndUpdateAllVaults();
      await mVault.setDepositFee(0, 0);
      await mVault.setWithdrawFee(0, 0);
      await time.increase(ONE_WEEK_IN_SECS);

      for (var i = 0; i < aprs.length; i++) {
        //console.log("");
        //console.log("Doing APR", aprs[i]);

        await mVault.deposit(0, 600 * 10 ** 6);
        await time.increase(ONE_DAY_IN_SECS);
        await mHub.setApr(0);
        await mVault.refreshAndUpdateAllVaults();
        await mHub.setApr(aprs[i] * 100);
        const timeBefore = await time.latest();
        let staked = await mVault.vaultTotalStaked(0);
        const earnPerSec = ethers.BigNumber.from(Math.round(staked * aprs[i] / (100 * ONE_YEAR_IN_SECS)));
        await time.increase(ONE_WEEK_IN_SECS);
        await mVault.refreshAndUpdateAllVaults();
        const lapse = (await time.latest()) - timeBefore;
        //console.log("Staked", staked);
        //console.log("earnPerSec", earnPerSec);
        //console.log("lapse", lapse);
        let newStaked: ethers.BigNumber = await mVault.vaultTotalStaked(0);
        let profit = ethers.BigNumber.from(earnPerSec).mul(lapse);
        //console.log("newStaked", newStaked);
        //console.log("profit", profit);
        let expected = ethers.BigNumber.from(staked).add(profit);
        //console.log("1st expected", expected);
        let realApr = aprs[i];
        if (expected.lte(0)) {
          expected = ethers.BigNumber.from(0);
          realApr = -100 * ONE_YEAR_IN_SECS / lapse;
        }

        /*console.log("Check staked");
        console.log("apr", aprs[i]);
        console.log("staked", staked);
        console.log("earnPerSec", earnPerSec);
        console.log("lapse", lapse);
        console.log("newStaked", newStaked);
        console.log("expected", expected);*/
        expect(newStaked).to.be.closeTo(expected, Math.round(expected / 1000), `APR earned is not what expected to be (${i})`);

        //console.log("Check apr");
        let aprsVault = await mVault.getLastPeriodsApr(0);
        //console.log("aprsVault", aprsVault);
        expect(aprsVault[0] / 100).to.be.closeTo(realApr, Math.abs(realApr / 1000), `APR calculated by vault is not what is earned (${i})`);

        staked = newStaked;
        /*console.log("Staked", newStaked);
        console.log("Apr", apr);*/
      }

    });

    it("Should properly calculate swap and perform it, in both directions", async function () {
      const SECONDS_PER_DAY = 24 * 3600;

      //Test battery: https://docs.google.com/spreadsheets/d/1OBsrnXMI5orVMv7alr9ZSxZ4F0rT6xvfJxqut-F71yY/edit#gid=765633564
      const TEST = [{ "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0.85, "STK0": 1.406917808219178, "STK1": 11.438356164383562, "EXCH0": 1.143835616438356, "EXCH1": 1.143835616438356, "IN": 0.2, "OUT": 2.817947368421053 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0, "STK0": 1.406917808219178, "STK1": 11.438356164383562, "EXCH0": 1.143835616438356, "EXCH1": 1.143835616438356, "IN": 0.13, "OUT": 1.8473684210526313 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0, "STK0": 1.406917808219178, "STK1": 11.438356164383562, "EXCH0": 1.143835616438356, "EXCH1": 1.143835616438356, "IN": 0.86, "OUT": 12.221052631578948 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0, "STK0": 1.406917808219178, "STK1": 11.438356164383562, "EXCH0": 1.143835616438356, "EXCH1": 1.143835616438356, "IN": 0.46, "OUT": 6.536842105263158 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 123, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0, "STK0": 1.3543479452054794, "STK1": 11.01095890410959, "EXCH0": 1.101095890410959, "EXCH1": 1.101095890410959, "IN": 1.2, "OUT": 17.052631578947366 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 123, "TIME0": 30, "TIME1": 30, "SWAPFEE": 1.24, "STK0": 1.3543479452054794, "STK1": 11.01095890410959, "EXCH0": 1.101095890410959, "EXCH1": 1.101095890410959, "IN": 0.08, "OUT": 1.122745263157895 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 123, "TIME0": 30, "TIME1": 60, "SWAPFEE": 5.22, "STK0": 1.3543479452054794, "STK1": 12.021917808219179, "EXCH0": 1.101095890410959, "EXCH1": 1.2021917808219178, "IN": 0.36, "OUT": 4.440999820563259 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 123, "TIME0": 30, "TIME1": 60, "SWAPFEE": 2.01, "STK0": 1.3543479452054794, "STK1": 12.021917808219179, "EXCH0": 1.101095890410959, "EXCH1": 1.2021917808219178, "IN": 0.09, "OUT": 1.1478517947272466 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -150, "TIME0": 30, "TIME1": 30, "SWAPFEE": 4.3, "STK0": 1.0783561643835617, "STK1": 8.767123287671232, "EXCH0": 0.8767123287671234, "EXCH1": 0.8767123287671232, "IN": 0.62, "OUT": 8.431673684210526 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -150, "TIME0": 30, "TIME1": 30, "SWAPFEE": 3.73, "STK0": 1.0783561643835617, "STK1": 8.767123287671232, "EXCH0": 0.8767123287671234, "EXCH1": 0.8767123287671232, "IN": 0.05, "OUT": 0.6840236842105265 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -150, "TIME0": 30, "TIME1": 30, "SWAPFEE": 8.37, "STK0": 1.0783561643835617, "STK1": 8.767123287671232, "EXCH0": 0.8767123287671234, "EXCH1": 0.8767123287671232, "IN": 0.82, "OUT": 10.677306315789473 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -150, "TIME0": 30, "TIME1": 30, "SWAPFEE": 6.77, "STK0": 1.0783561643835617, "STK1": 8.767123287671232, "EXCH0": 0.8767123287671234, "EXCH1": 0.8767123287671232, "IN": 0.17, "OUT": 2.25224052631579 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -57, "TIME0": 5, "TIME1": 30, "SWAPFEE": 9.78, "STK0": 1.2203958904109589, "STK1": 9.531506849315068, "EXCH0": 0.9921917808219178, "EXCH1": 0.9531506849315068, "IN": 1.13, "OUT": 15.080838538448734 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -57, "TIME0": 5, "TIME1": 30, "SWAPFEE": 1.7, "STK0": 1.2203958904109589, "STK1": 9.531506849315068, "EXCH0": 0.9921917808219178, "EXCH1": 0.9531506849315068, "IN": 0.73, "OUT": 10.615014749398648 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -57, "TIME0": 30, "TIME1": 60, "SWAPFEE": 5.73, "STK0": 1.1723753424657535, "STK1": 9.063013698630137, "EXCH0": 0.9531506849315069, "EXCH1": 0.9063013698630137, "IN": 0.79, "OUT": 11.130115969102016 }, { "SOURCE": 2, "DEST": 1, "DEP0": 1.23, "DEP1": 10, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -57, "TIME0": 30, "TIME1": 60, "SWAPFEE": 5.84, "STK0": 1.1723753424657535, "STK1": 9.063013698630137, "EXCH0": 0.9531506849315069, "EXCH1": 0.9063013698630137, "IN": 0.06, "OUT": 0.8443388862725132 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 6.91, "STK0": 14.492397260273972, "STK1": 1.6814383561643835, "EXCH0": 1.143835616438356, "EXCH1": 1.143835616438356, "IN": 1.13, "OUT": 0.0740237888888889 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 4.22, "STK0": 14.492397260273972, "STK1": 1.6814383561643835, "EXCH0": 1.143835616438356, "EXCH1": 1.143835616438356, "IN": 1.4, "OUT": 0.09436103703703702 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0.01, "STK0": 14.492397260273972, "STK1": 1.6814383561643835, "EXCH0": 1.143835616438356, "EXCH1": 1.143835616438356, "IN": 4.7, "OUT": 0.3307076666666667 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 9.39, "STK0": 14.492397260273972, "STK1": 1.6814383561643835, "EXCH0": 1.143835616438356, "EXCH1": 1.143835616438356, "IN": 0.54, "OUT": 0.034431800000000005 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 123, "TIME0": 15, "TIME1": 20, "SWAPFEE": 6.42, "STK0": 13.310442465753425, "STK1": 1.5690739726027396, "EXCH0": 1.0505479452054796, "EXCH1": 1.0673972602739725, "IN": 7.97, "OUT": 0.5165602611348773 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 123, "TIME0": 15, "TIME1": 20, "SWAPFEE": 9.58, "STK0": 13.310442465753425, "STK1": 1.5690739726027396, "EXCH0": 1.0505479452054796, "EXCH1": 1.0673972602739725, "IN": 7.79, "OUT": 0.48784469992870194 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 123, "TIME0": 15, "TIME1": 20, "SWAPFEE": 8.46, "STK0": 13.310442465753425, "STK1": 1.5690739726027396, "EXCH0": 1.0505479452054796, "EXCH1": 1.0673972602739725, "IN": 6.47, "OUT": 0.4101992098343981 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 123, "TIME0": 15, "TIME1": 20, "SWAPFEE": 5.78, "STK0": 13.310442465753425, "STK1": 1.5690739726027396, "EXCH0": 1.0505479452054796, "EXCH1": 1.0673972602739725, "IN": 6.74, "OUT": 0.4398277503555405 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -150, "TIME0": 15, "TIME1": 20, "SWAPFEE": 1.9, "STK0": 11.888972602739726, "STK1": 1.3491780821917807, "EXCH0": 0.9383561643835616, "EXCH1": 0.9178082191780821, "IN": 5.1, "OUT": 0.3599521641791045 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -150, "TIME0": 15, "TIME1": 20, "SWAPFEE": 1.85, "STK0": 11.888972602739726, "STK1": 1.3491780821917807, "EXCH0": 0.9383561643835616, "EXCH1": 0.9178082191780821, "IN": 4.2, "OUT": 0.29658228026534006 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -150, "TIME0": 12, "TIME1": 48, "SWAPFEE": 2.99, "STK0": 12.04517808219178, "STK1": 1.180027397260274, "EXCH0": 0.9506849315068493, "EXCH1": 0.8027397260273973, "IN": 7.41, "OUT": 0.5990821832006067 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -150, "TIME0": 12, "TIME1": 48, "SWAPFEE": 5.81, "STK0": 12.04517808219178, "STK1": 1.180027397260274, "EXCH0": 0.9506849315068493, "EXCH1": 0.8027397260273973, "IN": 7.54, "OUT": 0.591872053065352 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -57, "TIME0": 12, "TIME1": 48, "SWAPFEE": 9.91, "STK0": 12.432567671232876, "STK1": 1.3598104109589042, "EXCH0": 0.9812602739726027, "EXCH1": 0.9250410958904111, "IN": 9.76, "OUT": 0.6563559569403308 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -57, "TIME0": 12, "TIME1": 48, "SWAPFEE": 0.85, "STK0": 12.432567671232876, "STK1": 1.3598104109589042, "EXCH0": 0.9812602739726027, "EXCH1": 0.9250410958904111, "IN": 5.23, "OUT": 0.3870859730811252 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -57, "TIME0": 12, "TIME1": 48, "SWAPFEE": 6.53, "STK0": 12.432567671232876, "STK1": 1.3598104109589042, "EXCH0": 0.9812602739726027, "EXCH1": 0.9250410958904111, "IN": 8.93, "OUT": 0.6230698380242818 }, { "SOURCE": 1, "DEST": 2, "DEP0": 12.67, "DEP1": 1.47, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -57, "TIME0": 12, "TIME1": 48, "SWAPFEE": 1.01, "STK0": 12.432567671232876, "STK1": 1.3598104109589042, "EXCH0": 0.9812602739726027, "EXCH1": 0.9250410958904111, "IN": 2.78, "OUT": 0.20542303754250635 }];

      const TOLERANCE = 0.0000001; //0.00001% tolerance in differences because of bignumber handling

      const toBN = (num: Number, dec: Number): ethers.BigNumber => {
        return ethers.BigNumber.from(new BigNumber(num.toString() + "E" + dec.toString()).decimalPlaces(0).toString());
      }

      for (var i = 0; i < TEST.length; i++) {
        console.log("################ITERATION##################", i);

        var t = TEST[i];

        ({ mVault, mHub, tk, pFeed } = await loadFixture(deployMuchoVault));
        await createVaults();
        await mVault.setOpenAllVault(true);
        await mHub.setApr(t.APR * 100);

        //Transfer tokens to user:
        for(var j = 0; j < tk.length; j++){
          const ct = await ethers.getContractAt("ERC20", tk[j].t);
          const am = await ct.balanceOf(admin.address);
          await ct.transfer(user.address, am);
        }

        //Time difference between both deposits
        const depositTimeDiff = t.TIME1 - t.TIME0;

        console.log("Make destination vault deposit (longer timing)");
        console.log("Deposit Destination");
        await mVault.connect(user).deposit(t.DEST, toBN(t.DEP1, t.DEC1));

        if (depositTimeDiff > 0){
          console.log("Waiting aditional time for destination deposit");
          await time.increase(depositTimeDiff * SECONDS_PER_DAY - 1);
        }
          
        console.log("Make source vault deposit (longer timing)");
        await mVault.connect(user).deposit(t.SOURCE, toBN(t.DEP0, t.DEC0));

        console.log("Generate final APR for both")
        await time.increase(t.TIME0 * SECONDS_PER_DAY - 1);
        await mVault.refreshAndUpdateAllVaults();

        //Expected staked values in BN:
        const bigStkSrc = toBN(t.STK0, t.DEC0);
        const bigStkDst = toBN(t.STK1, t.DEC1);

        console.log("Assert staked tokens after APR");
        const amountSource = await mVault.connect(user).vaultTotalStaked(t.SOURCE);
        expect(amountSource).closeTo(bigStkSrc, Math.round(bigStkSrc * TOLERANCE), "Total source staked after APR is not correct");
        const amountDest = await mVault.connect(user).vaultTotalStaked(t.DEST);
        expect(amountDest).closeTo(bigStkDst, Math.round(bigStkDst * TOLERANCE), "Total dest staked after APR is not correct");

        console.log("Assert exchange mucho - normal token is what expected");
        const bigExch0 = toBN(t.EXCH0, 18);
        const bigExch1 = toBN(t.EXCH1, 18);
        const contractExchSrc = await mVault.connect(user).muchoTokenToDepositTokenPrice(t.SOURCE);
        const contractExchDst = await mVault.connect(user).muchoTokenToDepositTokenPrice(t.DEST);
        expect(contractExchSrc).closeTo(bigExch0, Math.round(bigExch0 * TOLERANCE), "Mucho exchange for source vault not correct");
        expect(contractExchDst).closeTo(bigExch1, Math.round(bigExch1 * TOLERANCE), "Mucho exchange for dest vault not correct");

        console.log("Assert mucho dest token got after swap is what expected");
        const inAmount = toBN(t.IN, t.DEC0);
        await mVault.setSwapMuchoTokensFee((t.SWAPFEE * 100).toFixed(0));
        const bigOut = toBN(t.OUT, t.DEC1);
        const swapRes = await mVault.connect(user).getSwap(t.SOURCE, inAmount, t.DEST);
        expect(swapRes).closeTo(bigOut, Math.round(bigOut * TOLERANCE), "Mucho swap out value is not correct");

        console.log("Assert swap performs how expected");
        const initialM0 = await (await ethers.getContractAt("MuchoToken", tk[t.SOURCE].m)).balanceOf(user.address);
        const initialM1 = await (await ethers.getContractAt("MuchoToken", tk[t.DEST].m)).balanceOf(user.address);
        console.log("Initial mucho source", initialM0);
        console.log("Initial mucho dest", initialM1);
        await mVault.connect(user).swap(t.SOURCE, inAmount, t.DEST, swapRes, 0);
        const finalM0 = await (await ethers.getContractAt("MuchoToken", tk[t.SOURCE].m)).balanceOf(user.address);
        const finalM1 = await (await ethers.getContractAt("MuchoToken", tk[t.DEST].m)).balanceOf(user.address);
        console.log("Final mucho source", finalM0);
        console.log("Final mucho dest", finalM1);
        expect(initialM0.sub(finalM0)).equal(inAmount, "Final amount of muchotoken source is not what I expected");
        expect(finalM1.sub(initialM1)).equal(swapRes, "Final amount of muchotoken source is not what I expected");
      };
    });
  });

});
