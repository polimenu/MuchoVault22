import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MuchoHubMock, PriceFeedMock } from "../typechain-types";
import { BigNumber } from "bignumber.js";
import { formatBytes32String } from "ethers/lib/utils";
import { ethers as eth, getDefaultProvider } from "ethers";


describe("MuchoVaultTest", async function () {

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

    //Set ownerships
    const [admin, trader, user] = await ethers.getSigners();
    await mVault.grantRole(formatBytes32String("0"), admin.address);
    await mVault.grantRole(formatBytes32String("TRADER"), trader.address);

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
      , admin, trader, user, mBadge
    };
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
        expect(v.totalStaked).to.equal(0);
        expect(v.stakedFromDeposits).to.equal(0);
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
      expect((await mVault.connect(user).getVaultInfo(0)).totalStaked).to.equal(AMOUNT);
      expect((await mVault.connect(user).getVaultInfo(0)).stakedFromDeposits).to.equal(AMOUNT);
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
      await token.connect(user).approve(mHub.address, DEPOSIT);
      await mVault.connect(user).deposit(0, DEPOSIT);
      const ts = (await mVault.getVaultInfo(0)).totalStaked;
      expect(ts).equal(Math.round(DEPOSIT * (1 - FEE)));
      expect((await mVault.getVaultInfo(0)).stakedFromDeposits).to.equal(Math.round(DEPOSIT * (1 - FEE)));
      expect(await mVault.vaultTotalStaked(0)).to.equal(Math.round(DEPOSIT * (1 - FEE)));

      const mtoken = await ethers.getContractAt("MuchoToken", tk[0].m);
      expect(await mtoken.balanceOf(user.address)).to.equal(Math.round(DEPOSIT * (1 - FEE)));
      expect(await token.balanceOf(user.address)).to.equal(INITIAL_AMOUNT - DEPOSIT);
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
      await mVault.connect(user).withdraw(0, WITHDRAWN);
      expect((await mVault.getVaultInfo(0)).totalStaked).to.equal(EXPECTED);
      expect((await mVault.getVaultInfo(0)).stakedFromDeposits).to.equal(EXPECTED);
      expect(await mVault.vaultTotalStaked(0)).to.equal(EXPECTED);

      expect(await token.balanceOf(user.address)).to.equal(WITHDRAWN);
      expect(await mtoken.balanceOf(user.address)).to.equal(EXPECTED);

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
      await token.transfer(user.address, DEPOSITED);
      await token.connect(user).approve(mHub.address, DEPOSITED);
      await mVault.connect(user).deposit(0, DEPOSITED);
      await mVault.connect(user).withdraw(0, WITHDRAWN);
      const EXPECTED = DEPOSITED - WITHDRAWN;
      expect((await mVault.getVaultInfo(0)).totalStaked).to.equal(EXPECTED);
      expect((await mVault.getVaultInfo(0)).stakedFromDeposits).to.equal(EXPECTED);
      expect(await mVault.vaultTotalStaked(0)).to.equal(EXPECTED);

      expect(await token.balanceOf(user.address)).to.equal(Math.round(WITHDRAWN * (1 - FEE / 10000)));
      expect(await mtoken.balanceOf(user.address)).to.equal(EXPECTED);
    });
  });


  describe("Earn", async () => {

    it("Should earn 200% apr", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      const APR = 200;
      const DEPOSIT = 1431.157 * 10 ** 6;
      const token = await ethers.getContractAt("ERC20", tk[0].t);
      await token.transfer(user.address, DEPOSIT);
      await token.connect(user).approve(mHub.address, DEPOSIT);
      await mHub.setApr(APR * 100);
      await mVault.setOpenAllVault(true);
      await mVault.connect(user).deposit(0, DEPOSIT);
      await mVault.refreshAndUpdateAllVaults();
      const timeDeposited = await time.latest();

      const FROMDEP = Number(await mVault.connect(user).vaultStakedFromDeposits(0));
      const DEPOSITED = Number(await mVault.connect(user).vaultTotalStaked(0));
      const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
      const EARN_PER_SEC = DEPOSITED * (APR / 100) / ONE_YEAR_IN_SECS;

      /*console.log("APR", APR);
      console.log("DEPOSITED", DEPOSITED);
      console.log("EARN_PER_SEC", EARN_PER_SEC);
      console.log("ONE_YEAR_IN_SECS", ONE_YEAR_IN_SECS);*/

      //console.log("timeBefore", timeBefore);
      await time.increaseTo(timeDeposited + ONE_YEAR_IN_SECS);

      await mVault.refreshAndUpdateAllVaults();
      let timeAfter = await time.latest();
      let lapse = timeAfter - timeDeposited;

      /*console.log("timeDeposited", timeDeposited);
      console.log("timeAfter", timeAfter);
      console.log("lapse", lapse);*/

      let staked = await mVault.connect(user).vaultTotalStaked(0);
      const EXPECTED = DEPOSITED + EARN_PER_SEC * lapse;
      //console.log("EXPECTED", EXPECTED);
      expect(staked).closeTo(Math.round(EXPECTED), Math.round(EXPECTED / 10000000), `Staked value after APR is not correct`);
      expect(await mVault.connect(user).vaultStakedFromDeposits(0)).to.equal(FROMDEP);
    });

    it("Should earn and measure properly several positive aprs, without deposits in the middle", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);

      //Make initial deposit
      const DEPOSIT = 1431.157 * 10 ** 6;
      const token = await ethers.getContractAt("ERC20", tk[0].t);
      await token.transfer(user.address, DEPOSIT);
      await token.connect(user).approve(mHub.address, DEPOSIT);
      await mVault.setOpenAllVault(true);
      const dp = await mVault.connect(user).deposit(0, DEPOSIT);
      const rc = await dp.wait();
      const dpe = rc.events.find(e => e.event === 'Deposited');
      console.log("Deposited log", dpe);

      const aprs = [153, 14, 27, 3141, 10000];
      const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;

      //console.log("ALLA VAMOS----------------------------------------------");

      await mVault.refreshAndUpdateAllVaults();
      await time.increase(ONE_YEAR_IN_SECS);
      await mVault.refreshAndUpdateAllVaults();
      await time.increase(ONE_YEAR_IN_SECS);

      for (var i = 0; i < aprs.length; i++) {
        await mHub.setApr(aprs[i] * 100);
        await mVault.refreshAndUpdateAllVaults();
        let staked: eth.BigNumber = await mVault.connect(user).vaultTotalStaked(0);
        const earnPerSec = Number(staked) * aprs[i] / (100 * ONE_YEAR_IN_SECS);
        const timeBefore = await time.latest();
        await time.increase(ONE_YEAR_IN_SECS);
        await mVault.refreshAndUpdateAllVaults();
        const lapse = (await time.latest()) - timeBefore;
        //console.log("Staked", staked);
        let newStaked = await mVault.connect(user).vaultTotalStaked(0);
        let expected = eth.BigNumber.from(staked).add(Math.round(earnPerSec * lapse));

        /*console.log("Check staked");
        console.log("apr", aprs[i]);
        console.log("staked", staked);
        console.log("earnPerSec", earnPerSec);
        console.log("lapse", lapse);
        console.log("newStaked", newStaked);
        console.log("expected", expected);*/
        expect(newStaked).to.be.closeTo(expected, expected.div(100000), "APR earned is not what expected to be (${i})");

        //console.log("Check apr");
        

        //Compute APR - SAVE IT FOR THE FUTURE
        /*
        const ifaceDeps = new ethers.utils.Interface(["event Deposited(address user, uint8 vaultId, uint256 amount)"]);
        const ifaceWdws = new ethers.utils.Interface(["event Withdrawn(address user, uint8 vaultId, uint256 amount, uint256 mamount)"]);
        const depLogs = await ethers.provider.getLogs({
          address: mVault.address,
          topics: [eth.utils.id("Deposited(address,uint8,uint256)")],
          fromBlock: 0,
          toBlock: "latest"
        });
        const wdwLogs = await ethers.provider.getLogs({
          address: mVault.address,
          topics: [eth.utils.id("Withdrawn(address,uint8,uint256,uint256)")],
          fromBlock: 0,
          toBlock: "latest"
        });
        console.log("DEPOSITS: ", depLogs);
        console.log("WITHDRAWNS: ", wdwLogs);

        const vaultMoves:number[][] = [];
        for(var il in depLogs){
          const log = depLogs[il];
          const pLog = ifaceDeps.parseLog(log);
          const [from, vault, amount, ts] = [...pLog.args, (await ethers.provider.getBlock(log.blockNumber)).timestamp];
          console.log("Deposit from", from);
          console.log("Deposit vault", vault);
          console.log("Deposit amount", amount);
          console.log("Deposit ts", ts);
          vaultMoves[vault][ts] = fromBN(amount, 0);
        }
        for(var il in wdwLogs){
          const log = wdwLogs[il];
          const pLog = ifaceWdws.parseLog(log);
          const [from, vault, amount, ts] = [pLog.args[0],
                                              Number.parseInt(pLog.args[1]),
                                              pLog.args[2], 
                                              (await ethers.provider.getBlock(log.blockNumber)).timestamp];
          console.log("Withdraw from", from);
          console.log("Withdraw vault", vault);
          console.log("Withdraw amount", amount);
          console.log("Withdraw ts", ts);
          vaultMoves[vault][ts] = -fromBN(amount, 0);
        }
        let lastTs = 0, lastDep = 0; let firstTs = 0; let firstDep = 0;
        let accumVal = 0;
        for(var im in vaultMoves[0]){
          const m = vaultMoves[0][im];
          if(lastDep == 0){
            lastDep = m;
            lastTs = im;
            firstTs = im;
            firstDep = m;
          }
          else{
            accumVal += lastDep * (im - lastTs);
            lastDep = lastDep + m;
            lastTs = im;
          }
        }
        const curVal = await mVault.vaultTotalStaked(0);
        const latestTs = await time.latest();
        accumVal += lastDep * (latestTs - lastTs);
        const avgDep = accumVal / (latestTs - firstTs);
        const profit = (curVal - firstDep) / avgDep;
        */

        staked = newStaked;
        /*console.log("Staked", newStaked);
        console.log("Apr", apr);*/
      }

    });


    it("Should earn and measure properly several negative aprs, without deposits in the middle", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      const aprs = [-153, -14, -27, -3141, -3650000];
      const ONE_DAY_IN_SECS = 24 * 60 * 60;
      const ONE_MONTH_IN_SECS = 30 * ONE_DAY_IN_SECS;
      const ONE_YEAR_IN_SECS = 365 * ONE_DAY_IN_SECS;

      //Make initial deposit
      const DEPOSIT = 1431.157 * 10 ** 6;
      const token = await ethers.getContractAt("ERC20", tk[0].t);
      await token.transfer(user.address, DEPOSIT);
      await token.connect(user).approve(mHub.address, DEPOSIT);
      await mVault.setOpenAllVault(true);
      await mVault.connect(user).deposit(0, DEPOSIT);

      //console.log("ALLA VAMOS----------------------------------------------");

      await mVault.refreshAndUpdateAllVaults();
      await time.increase(ONE_DAY_IN_SECS);

      for (var i = 0; i < aprs.length; i++) {
        await mHub.setApr(aprs[i] * 100);
        await mVault.refreshAndUpdateAllVaults();
        let staked = await mVault.connect(user).vaultTotalStaked(0);
        //const earnPerSec = staked * aprs[i] / (100 * ONE_YEAR_IN_SECS);//eth.BigNumber.from(staked).mul(aprs[i]).div(100).div(ONE_YEAR_IN_SECS);
        const timeBefore = await time.latest();
        await time.increase(ONE_DAY_IN_SECS);
        await mVault.refreshAndUpdateAllVaults();
        const lapse = (await time.latest()) - timeBefore;
        //console.log("Doing APR", aprs[i]);
        //console.log("Staked", staked);
        const newStaked: eth.BigNumber = await mVault.connect(user).vaultTotalStaked(0);
        const profit: eth.BigNumber = eth.BigNumber.from(staked).mul(aprs[i]).mul(lapse).div(100).div(ONE_YEAR_IN_SECS);   //eth.BigNumber.from(earnPerSec).mul(lapse);
        //console.log("profit", profit);
        let expected: eth.BigNumber = eth.BigNumber.from(staked).add(profit);
        //console.log("1st expected", expected);
        let realApr = aprs[i];
        if (expected.lt(0)) {
          expected = eth.BigNumber.from(0);
          realApr = -100 * ONE_YEAR_IN_SECS / lapse;
        }

        /*console.log("Check staked");
        console.log("apr", aprs[i]);
        console.log("staked", staked);
        console.log("earnPerSec", earnPerSec);
        console.log("lapse", lapse);
        console.log("newStaked", newStaked);
        console.log("expected", expected);*/
        expect(newStaked).equal(expected, `APR earned is not what expected to be (${i})`);

        //console.log("Check apr");
        //const aprsVault: eth.BigNumber[] = await mVault.getLastPeriodsApr(0);
        //console.log("aprsVault", aprsVault);
        //expect(Number(aprsVault[0]) / 100).to.be.closeTo(realApr, Math.abs(realApr / 1000), `APR calculated by vault is not what is earned (${i})`);

        staked = newStaked;
        /*console.log("Staked", newStaked);
        console.log("Apr", apr);*/
      }

    });

    it("Should earn and measure properly several positive and negative aprs, WITH deposits in the middle", async function () {
      const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
      const aprs = [153, 34, -27, -3141, -3650000];
      const ONE_DAY_IN_SECS = 24 * 60 * 60;
      const ONE_WEEK_IN_SECS = 7 * ONE_DAY_IN_SECS;
      const ONE_YEAR_IN_SECS = 365 * ONE_DAY_IN_SECS;
      const DEPOSIT = 600 * 10 ** 6;

      //Make initial deposit
      const token = await ethers.getContractAt("ERC20", tk[0].t);
      const totalBlc = await token.balanceOf(admin.address);
      await token.transfer(user.address, totalBlc);
      await mVault.setOpenAllVault(true);

      await mVault.setAprUpdatePeriod(3600);

      //console.log("ALLA VAMOS----------------------------------------------");

      await mVault.refreshAndUpdateAllVaults();
      await mVault.setDepositFee(0, 0);
      await mVault.setWithdrawFee(0, 0);
      await time.increase(ONE_WEEK_IN_SECS);

      for (var i = 0; i < aprs.length; i++) {
        //console.log("");
        //console.log("Doing APR", aprs[i]);
        await token.connect(user).approve(mHub.address, DEPOSIT);
        await mVault.connect(user).deposit(0, DEPOSIT);
        await time.increase(ONE_DAY_IN_SECS);
        await mHub.setApr(0);
        await mVault.refreshAndUpdateAllVaults();
        await mHub.setApr(aprs[i] * 100);
        const timeBefore = await time.latest();
        let staked: eth.BigNumber = await mVault.connect(user).vaultTotalStaked(0);
        const earnPerSec = eth.BigNumber.from(Math.round(Number(staked) * aprs[i] / (100 * ONE_YEAR_IN_SECS)));
        await time.increase(ONE_WEEK_IN_SECS);
        await mVault.refreshAndUpdateAllVaults();
        const lapse = (await time.latest()) - timeBefore;
        //console.log("Staked", staked);
        //console.log("earnPerSec", earnPerSec);
        //console.log("lapse", lapse);
        let newStaked: eth.BigNumber = await mVault.connect(user).vaultTotalStaked(0);
        let profit = eth.BigNumber.from(earnPerSec).mul(lapse);
        //console.log("newStaked", newStaked);
        //console.log("profit", profit);
        let expected = eth.BigNumber.from(staked).add(profit);
        //console.log("1st expected", expected);
        let realApr = aprs[i];
        if (expected.lte(0)) {
          expected = eth.BigNumber.from(0);
          realApr = -100 * ONE_YEAR_IN_SECS / lapse;
        }

        /*console.log("Check staked");
        console.log("apr", aprs[i]);
        console.log("staked", staked);
        console.log("earnPerSec", earnPerSec);
        console.log("lapse", lapse);
        console.log("newStaked", newStaked);
        console.log("expected", expected);*/
        expect(newStaked).to.be.closeTo(expected, Math.round(Number(expected) / 1000), `APR earned is not what expected to be (${i})`);

        //console.log("Check apr");
        //let aprsVault: eth.BigNumber[] = await mVault.connect(user).getLastPeriodsApr(0);
        //console.log("aprsVault", aprsVault);
        //expect(Number(aprsVault[0]) / 100).to.be.closeTo(realApr, Math.abs(realApr / 1000), `APR calculated by vault is not what is earned (${i})`);

        staked = newStaked;
        /*console.log("Staked", newStaked);
        console.log("Apr", apr);*/
      }

    });
  });

  describe("Swap", async () => {

    it("Swap battery without NFT", async function () {
      const SECONDS_PER_DAY = 24 * 3600;

      //Test battery: https://docs.google.com/spreadsheets/d/1OBsrnXMI5orVMv7alr9ZSxZ4F0rT6xvfJxqut-F71yY/edit#gid=765633564
      const TEST = [{ "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0.85, "STK0": 14.069177399638509, "STK1": 114.38356164383562, "EXCH0": 1.14383556094622, "EXCH1": 1.1438356164383563, "IN": 0.2, "OUT": 2.81794723171092, "ENDSTK0": 13.842354807902874, "ENDSTK1": 117.60683005271044 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0, "STK0": 14.069177399638509, "STK1": 114.38356164383562, "EXCH0": 1.14383556094622, "EXCH1": 1.1438356164383563, "IN": 0.13, "OUT": 1.8473683314292464, "ENDSTK0": 13.9204787767155, "ENDSTK1": 116.49664733800469 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0, "STK0": 14.069177399638509, "STK1": 114.38356164383562, "EXCH0": 1.14383556094622, "EXCH1": 1.1438356164383563, "IN": 0.6315, "OUT": 8.973946933058222, "ENDSTK0": 13.34684524290097, "ENDSTK1": 124.64828176589536 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0, "STK0": 14.069177399638509, "STK1": 114.38356164383562, "EXCH0": 1.14383556094622, "EXCH1": 1.1438356164383563, "IN": 0.46, "OUT": 6.536841788134257, "ENDSTK0": 13.543013041603247, "ENDSTK1": 121.86063410012618 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 123, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0, "STK0": 13.543478972317352, "STK1": 110.10958904109589, "EXCH0": 1.1010958514079148, "EXCH1": 1.101095890410959, "IN": 0.6943, "OUT": 9.866368071565901, "ENDSTK0": 12.778988122684837, "ENDSTK1": 120.973406377979 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 123, "TIME0": 30, "TIME1": 30, "SWAPFEE": 1.24, "STK0": 13.543478972317352, "STK1": 110.10958904109589, "EXCH0": 1.1010958514079148, "EXCH1": 1.101095890410959, "IN": 0.08, "OUT": 1.1227452233879862, "ENDSTK0": 13.456483591289317, "ENDSTK1": 111.34583919254693 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 123, "TIME0": 30, "TIME1": 60, "SWAPFEE": 5.22, "STK0": 13.543479452054795, "STK1": 120.21917808219177, "EXCH0": 1.101095890410959, "EXCH1": 1.2021917808219178, "IN": 0.36, "OUT": 4.440999820563259, "ENDSTK0": 13.167776725479452, "ENDSTK1": 125.55811156510454 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": 123, "TIME0": 30, "TIME1": 60, "SWAPFEE": 2.01, "STK0": 13.543479452054795, "STK1": 120.21917808219177, "EXCH0": 1.101095890410959, "EXCH1": 1.2021917808219178, "IN": 0.09, "OUT": 1.1478517947272466, "ENDSTK0": 13.446372704383561, "ENDSTK1": 121.59911607541456 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -150, "TIME0": 30, "TIME1": 30, "SWAPFEE": 4.3, "STK0": 10.783562228881278, "STK1": 87.67123287671232, "EXCH0": 0.8767123763318112, "EXCH1": 0.8767123287671232, "IN": 0.62, "OUT": 8.431674141658101, "ENDSTK0": 10.263373707508562, "ENDSTK1": 95.06338554885093 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -150, "TIME0": 30, "TIME1": 30, "SWAPFEE": 3.73, "STK0": 10.783562228881278, "STK1": 87.67123287671232, "EXCH0": 0.8767123763318112, "EXCH1": 0.8767123287671232, "IN": 0.05, "OUT": 0.6840237213211863, "ENDSTK0": 10.741361678646546, "ENDSTK1": 88.27092490636377 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -150, "TIME0": 30, "TIME1": 30, "SWAPFEE": 8.37, "STK0": 10.783562228881278, "STK1": 87.67123287671232, "EXCH0": 0.8767123763318112, "EXCH1": 0.8767123287671232, "IN": 0.74352, "OUT": 9.681452710515554, "ENDSTK0": 10.186269154503455, "ENDSTK1": 96.15908182839719 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -150, "TIME0": 30, "TIME1": 30, "SWAPFEE": 6.77, "STK0": 10.783562228881278, "STK1": 87.67123287671232, "EXCH0": 0.8767123763318112, "EXCH1": 0.8767123287671232, "IN": 0.17, "OUT": 2.2522406485076583, "ENDSTK0": 10.644611207644074, "ENDSTK1": 89.64580002060944 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -57, "TIME0": 5, "TIME1": 30, "SWAPFEE": 9.78, "STK0": 12.203958904109589, "STK1": 95.31506849315069, "EXCH0": 0.9921917808219177, "EXCH1": 0.9531506849315069, "IN": 0.6135, "OUT": 8.187694197644515, "ENDSTK0": 11.654781051082193, "ENDSTK1": 103.11917482564529 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -57, "TIME0": 5, "TIME1": 30, "SWAPFEE": 1.7, "STK0": 12.203958904109589, "STK1": 95.31506849315069, "EXCH0": 0.9921917808219177, "EXCH1": 0.9531506849315069, "IN": 0.64354, "OUT": 9.357789851819186, "ENDSTK0": 11.576298562156165, "ENDSTK1": 104.23445229985725 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -57, "TIME0": 30, "TIME1": 60, "SWAPFEE": 5.73, "STK0": 11.723753424657534, "STK1": 90.63013698630137, "EXCH0": 0.9531506849315068, "EXCH1": 0.9063013698630137, "IN": 0.70015, "OUT": 9.864241387046553, "ENDSTK0": 11.09464403890548, "ENDSTK1": 99.57011246804109 }, { "SOURCE": 2, "DEST": 1, "DEP0": 12.3, "DEP1": 100, "DEC0": 12, "DEC1": 18, "PRICE0": 27000, "PRICE1": 1900, "APR": -57, "TIME0": 30, "TIME1": 60, "SWAPFEE": 5.84, "STK0": 11.723753424657534, "STK1": 90.63013698630137, "EXCH0": 0.9531506849315068, "EXCH1": 0.9063013698630137, "IN": 0.06, "OUT": 0.8443388862725131, "ENDSTK0": 11.669904223561645, "ENDSTK1": 91.39536247555876 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 6.91, "STK0": 144.9239655718861, "STK1": 16.814383561643837, "EXCH0": 1.14383556094622, "EXCH1": 1.1438356164383563, "IN": 1.13, "OUT": 0.07402378529769266, "ENDSTK0": 143.72074550012223, "ENDSTK1": 16.899054603730924 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 4.22, "STK0": 144.9239655718861, "STK1": 16.814383561643837, "EXCH0": 1.14383556094622, "EXCH1": 1.1438356164383563, "IN": 1.4, "OUT": 0.09436103245919782, "ENDSTK0": 143.3901735915021, "ENDSTK1": 16.922317071374565 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 0.01, "STK0": 144.9239655718861, "STK1": 16.814383561643837, "EXCH0": 1.14383556094622, "EXCH1": 1.1438356164383563, "IN": 4.7, "OUT": 0.3307076506226874, "ENDSTK0": 139.5484760381525, "ENDSTK1": 17.19265875105472 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 175, "TIME0": 30, "TIME1": 30, "SWAPFEE": 9.39, "STK0": 144.9239655718861, "STK1": 16.814383561643837, "EXCH0": 1.14383556094622, "EXCH1": 1.1438356164383563, "IN": 0.54, "OUT": 0.0344317983295728, "ENDSTK0": 144.36429369492848, "ENDSTK1": 16.853767878911224 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 123, "TIME0": 15, "TIME1": 20, "SWAPFEE": 6.42, "STK0": 133.10442465753425, "STK1": 15.690739726027397, "EXCH0": 1.0505479452054796, "EXCH1": 1.0673972602739727, "IN": 7.97, "OUT": 0.5165602611348772, "ENDSTK0": 125.26909560356165, "ENDSTK1": 16.242114733529174 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 123, "TIME0": 15, "TIME1": 20, "SWAPFEE": 9.58, "STK0": 133.10442465753425, "STK1": 15.690739726027397, "EXCH0": 1.0505479452054796, "EXCH1": 1.0673972602739727, "IN": 7.79, "OUT": 0.48784469992870183, "ENDSTK0": 125.70466118602741, "ENDSTK1": 16.211463822170472 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 123, "TIME0": 15, "TIME1": 20, "SWAPFEE": 8.46, "STK0": 133.10442465753425, "STK1": 15.690739726027397, "EXCH0": 1.0505479452054796, "EXCH1": 1.0673972602739727, "IN": 6.47, "OUT": 0.410199209834398, "ENDSTK0": 126.88240947643837, "ENDSTK1": 16.128585238771183 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": 123, "TIME0": 15, "TIME1": 20, "SWAPFEE": 5.78, "STK0": 133.10442465753425, "STK1": 15.690739726027397, "EXCH0": 1.0505479452054796, "EXCH1": 1.0673972602739727, "IN": 6.74, "OUT": 0.4398277503555404, "ENDSTK0": 126.43299557095891, "ENDSTK1": 16.160210661749367 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -150, "TIME0": 15, "TIME1": 20, "SWAPFEE": 1.9, "STK0": 118.88972602739726, "STK1": 13.491780821917807, "EXCH0": 0.9383561643835616, "EXCH1": 0.9178082191780822, "IN": 5.1, "OUT": 0.3599521641791044, "ENDSTK0": 114.19503630136987, "ENDSTK1": 13.822147876712327 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -150, "TIME0": 15, "TIME1": 20, "SWAPFEE": 1.85, "STK0": 118.88972602739726, "STK1": 13.491780821917807, "EXCH0": 0.9383561643835616, "EXCH1": 0.9178082191780822, "IN": 4.2, "OUT": 0.29658228026534, "ENDSTK0": 115.0215404109589, "ENDSTK1": 13.763986476407913 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -150, "TIME0": 12, "TIME1": 48, "SWAPFEE": 2.99, "STK0": 120.45178082191781, "STK1": 11.800273972602739, "EXCH0": 0.9506849315068493, "EXCH1": 0.8027397260273972, "IN": 7.41, "OUT": 0.5990821832006068, "ENDSTK0": 113.61783828219178, "ENDSTK1": 12.281181040213088 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -150, "TIME0": 12, "TIME1": 48, "SWAPFEE": 5.81, "STK0": 120.45178082191781, "STK1": 11.800273972602739, "EXCH0": 0.9506849315068493, "EXCH1": 0.8027397260273972, "IN": 7.54, "OUT": 0.5918720530653521, "ENDSTK0": 113.7000867890411, "ENDSTK1": 12.275393182323693 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -57, "TIME0": 12, "TIME1": 48, "SWAPFEE": 9.91, "STK0": 124.32567671232877, "STK1": 13.598104109589041, "EXCH0": 0.9812602739726027, "EXCH1": 0.9250410958904111, "IN": 9.76, "OUT": 0.6563559569403308, "ENDSTK0": 115.69766707550686, "ENDSTK1": 14.205260343291323 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -57, "TIME0": 12, "TIME1": 48, "SWAPFEE": 0.85, "STK0": 124.32567671232877, "STK1": 13.598104109589041, "EXCH0": 0.9812602739726027, "EXCH1": 0.9250410958904111, "IN": 5.23, "OUT": 0.3870859730811252, "ENDSTK0": 119.23730740493151, "ENDSTK1": 13.956174542331812 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -57, "TIME0": 12, "TIME1": 48, "SWAPFEE": 6.53, "STK0": 124.32567671232877, "STK1": 13.598104109589041, "EXCH0": 0.9812602739726027, "EXCH1": 0.9250410958904111, "IN": 8.93, "OUT": 0.6230698380242818, "ENDSTK0": 116.1352237880548, "ENDSTK1": 14.174469315371283 }, { "SOURCE": 1, "DEST": 2, "DEP0": 126.7, "DEP1": 14.7, "DEC0": 18, "DEC1": 12, "PRICE0": 1900, "PRICE1": 27000, "APR": -57, "TIME0": 12, "TIME1": 48, "SWAPFEE": 1.01, "STK0": 124.32567671232877, "STK1": 13.598104109589041, "EXCH0": 0.9812602739726027, "EXCH1": 0.9250410958904111, "IN": 2.78, "OUT": 0.20542303754250635, "ENDSTK0": 121.62532497665754, "ENDSTK1": 13.788128861358498 }];

      for (var i = 0; i < TEST.length; i++) {
        console.log("################ITERATION##################", i);

        var t = TEST[i];

        //Tolerance because of excel rounding up to 15 figures
        const SOURCE_TOLERANCE = 10 ** ((t.DEC0 > 11) ? t.DEC0 - 12 : 0);
        const DEST_TOLERANCE = 10 ** ((t.DEC1 > 11) ? t.DEC1 - 12 : 0);
        const EXCHANGE_TOLERANCE = Math.max(SOURCE_TOLERANCE, DEST_TOLERANCE);



        console.log("test data", t);

        const { mVault, mHub, tk, pFeed, admin, trader, user } = await loadFixture(deployMuchoVault);
        await mVault.setOpenAllVault(true);
        await mHub.setApr(t.APR * 100);

        //Set prices
        await pFeed.addToken(tk[t.SOURCE].t, toBN(t.PRICE0, 18));
        await pFeed.addToken(tk[t.DEST].t, toBN(t.PRICE1, 18));

        //Transfer tokens to user and approve to be spent by the HUB:
        for (var j = 0; j < tk.length; j++) {
          const ct = await ethers.getContractAt("ERC20", tk[j].t);
          const am = await ct.balanceOf(admin.address);
          await ct.transfer(user.address, am);
          await ct.connect(user).approve(mHub.address, am);
        }

        //Time difference between both deposits
        const depositTimeDiff = t.TIME1 - t.TIME0;

        console.log("Make destination vault deposit (longer timing)");
        await mVault.connect(user).deposit(t.DEST, toBN(t.DEP1, t.DEC1));
        const timeDepositedDest = await time.latest();

        if (depositTimeDiff > 0) {
          console.log("Waiting aditional time for destination deposit");
          await time.setNextBlockTimestamp(timeDepositedDest + depositTimeDiff * SECONDS_PER_DAY);
        }
        else {
          await time.setNextBlockTimestamp(timeDepositedDest + 1); //Source will have always 1s less APR because can't be blocks with same timestamp
        }

        console.log("Make source vault deposit (longer timing)");
        await mVault.connect(user).deposit(t.SOURCE, toBN(t.DEP0, t.DEC0));

        console.log("Generate final APR for both")
        //await time.increase(t.TIME0 * SECONDS_PER_DAY - 1);
        await time.setNextBlockTimestamp(timeDepositedDest + t.TIME1 * SECONDS_PER_DAY);
        await mVault.refreshAndUpdateAllVaults();

        //Expected staked values in BN:
        const bigStkSrc = toBN(t.STK0, t.DEC0);
        const bigStkDst = toBN(t.STK1, t.DEC1);

        console.log("Assert staked tokens after APR");
        const amountSource = await mVault.connect(user).vaultTotalStaked(t.SOURCE);
        expect(amountSource).closeTo(bigStkSrc, SOURCE_TOLERANCE, "Total source staked after APR is not correct");
        const amountDest = await mVault.connect(user).vaultTotalStaked(t.DEST);
        expect(amountDest).closeTo(bigStkDst, DEST_TOLERANCE, "Total dest staked after APR is not correct");

        console.log("Assert exchange mucho - normal token is what expected");
        const bigExch0 = toBN(t.EXCH0, 18);
        const bigExch1 = toBN(t.EXCH1, 18);
        const contractExchSrc = await mVault.connect(user).muchoTokenToDepositTokenPrice(t.SOURCE);
        const contractExchDst = await mVault.connect(user).muchoTokenToDepositTokenPrice(t.DEST);
        expect(contractExchSrc).closeTo(bigExch0, EXCHANGE_TOLERANCE, "Mucho exchange for source vault not correct");
        expect(contractExchDst).closeTo(bigExch1, EXCHANGE_TOLERANCE, "Mucho exchange for dest vault not correct");

        console.log("Assert mucho dest token got after swap is what expected");
        const inAmount = toBN(t.IN, t.DEC0);
        await mVault.setSwapMuchoTokensFee((t.SWAPFEE * 100).toFixed(0));
        const bigOut = toBN(t.OUT, t.DEC1);
        const swapRes = await mVault.connect(user).getSwap(t.SOURCE, inAmount, t.DEST);
        expect(swapRes).closeTo(bigOut, EXCHANGE_TOLERANCE, "Mucho swap out value is not correct");

        console.log("Assert swap performs how expected");
        const initialM0 = await (await ethers.getContractAt("MuchoToken", tk[t.SOURCE].m)).balanceOf(user.address);
        const initialM1 = await (await ethers.getContractAt("MuchoToken", tk[t.DEST].m)).balanceOf(user.address);
        //console.log("Initial mucho source", initialM0);
        //console.log("Initial mucho dest", initialM1);
        await mVault.connect(user).swap(t.SOURCE, inAmount, t.DEST, swapRes, 0);
        const finalM0 = await (await ethers.getContractAt("MuchoToken", tk[t.SOURCE].m)).balanceOf(user.address);
        const finalM1 = await (await ethers.getContractAt("MuchoToken", tk[t.DEST].m)).balanceOf(user.address);
        //console.log("Final mucho source", finalM0);
        //console.log("Final mucho dest", finalM1);
        expect(initialM0.sub(finalM0)).equal(inAmount, "Final amount of muchotoken source is not what I expected");
        expect(finalM1.sub(initialM1)).equal(swapRes, "Final amount of muchotoken source is not what I expected");
        
        const endStk0 = await mVault.connect(user).vaultTotalStaked(t.SOURCE);
        const endStk1 = await mVault.connect(user).vaultTotalStaked(t.DEST);
        expect(endStk0).closeTo(toBN(t.ENDSTK0, t.DEC0), EXCHANGE_TOLERANCE, "End total staked source is not correct");
        expect(endStk1).closeTo(toBN(t.ENDSTK1, t.DEC1), EXCHANGE_TOLERANCE, "End total staked destination is not correct");
      };
    });


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

      const { mVault, mHub, tk, pFeed, admin, trader, user, mBadge } = await loadFixture(deployMuchoVault);

      //Add user to NFT plan 3 and 4
      await mBadge.addUserToPlan(user.address, 3);
      await mBadge.addUserToPlan(user.address, 4);

      //set Fees
      const FEE_STD = 150, FEE1 = 140, FEE_MIN = 120, FEE_MIN2 = 110, FEE_MIN3 = 75;
      await mVault.setSwapMuchoTokensFee(FEE_STD);
      await mVault.setSwapMuchoTokensFeeForPlan(3, FEE1);
      await mVault.setSwapMuchoTokensFeeForPlan(4, FEE_MIN);

      //Transfer tokens to user, approve to be spent by the HUB, and deposit them:
      await mVault.setOpenAllVault(true);
      for (var j = 0; j < tk.length; j++) {
        const ct = await ethers.getContractAt("ERC20", tk[j].t);
        const am = await ct.balanceOf(admin.address);
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


  });

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

      await expect(mVault.connect(user).setAprUpdatePeriod(1)).revertedWith(ONLY_ADMIN_REASON);
      await expect(mVault.connect(trader).setAprUpdatePeriod(1)).revertedWith(ONLY_ADMIN_REASON);

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
      await expect(mVault.connect(user).updateVault(1)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(mVault.connect(user).updateAllVaults()).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(mVault.connect(user).refreshAndUpdateAllVaults()).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
    });
  });
});
