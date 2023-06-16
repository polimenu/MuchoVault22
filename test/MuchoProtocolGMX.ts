import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MuchoHubMock, PriceFeedMock } from "../typechain-types";
import { BigNumber } from "bignumber.js";
import { formatBytes32String } from "ethers/lib/utils";
import { ethers as eth } from "ethers";
import { InvestmentPartStruct } from "../typechain-types/contracts/MuchoHub";


describe("MuchoProtocolGMXTest", async function () {

  const toBN = (num: Number, dec: Number): eth.BigNumber => {
    BigNumber.config({ EXPONENTIAL_AT: 100 });
    return eth.BigNumber.from(new BigNumber(num.toString() + "E" + dec.toString()).decimalPlaces(0).toString());
  }

  const fromBN = (bn: eth.BigNumber, dec: number): number => {
    return Number(bn) / (10 ** dec);
  }

  async function deployContract(name: string) {
    const [admin, trader, user] = await ethers.getSigners();
    const f = await ethers.getContractFactory(name);
    return f.connect(admin).deploy();
  }

  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployMuchoHub() {
    const [admin, owner, trader, user] = await ethers.getSigners();

    //Deploy ERC20 fakes
    const usdc = await deployContract("USDC");
    const weth = await deployContract("WETH");
    const wbtc = await deployContract("WBTC");
    const usdt = await deployContract("USDT");
    const dai = await deployContract("DAI");
    const glp = await deployContract("GLP");
    
    await usdc.mint(user.address, toBN(100000, 6));
    await weth.mint(user.address, toBN(100, 18));
    await wbtc.mint(user.address, toBN(10, 12));
    await usdt.mint(user.address, toBN(100000, 6));
    await dai.mint(user.address, toBN(100000, 6));

    //Deploy rest of mocks
    const glpVault = await (await ethers.getContractFactory("GLPVaultMock")).deploy();
    const glpPriceFeed = await (await ethers.getContractFactory("GLPPriceFeedMock")).deploy(usdc.address, weth.address, wbtc.address, glpVault.address, glp.address);
    const glpRewardRouter = await (await ethers.getContractFactory("GLPRewardRouterMock")).deploy();
    const glpRouter = await (await ethers.getContractFactory("GLPRouterMock")).deploy(glpVault.address, glp.address, usdc.address, weth.address, wbtc.address);
    

    const mHub = await (await ethers.getContractFactory("MuchoHub")).deploy();
    const f = await ethers.getContractFactory("PriceFeedMock");
    const pFeed = await f.deploy(usdc.address, weth.address, wbtc.address);
    const aprs = [1100, 2500, -700];
    const notInv = [0, 532, 300];
    const prot1 = await (await ethers.getContractFactory("MuchoProtocolMock")).deploy(aprs[0], notInv[0], pFeed.address);
    const prot2 = await (await ethers.getContractFactory("MuchoProtocolMock")).deploy(aprs[1], notInv[1], pFeed.address);
    const prot3 = await (await ethers.getContractFactory("MuchoProtocolMock")).deploy(aprs[2], notInv[2], pFeed.address);
    prot1.setPriceFeed(pFeed.address);
    prot2.setPriceFeed(pFeed.address);
    prot3.setPriceFeed(pFeed.address);

    //Set ownerships
    const TRADER_ROLE = await mHub.TRADER();
    await mHub.grantRole(eth.utils.formatBytes32String("0"), admin.address);
    await mHub.grantRole(TRADER_ROLE, trader.address);
    await mHub.transferOwnership(hubOwner.address);

    //Set mocks as contracts for vault
    expect((await mHub.protocols()).length).equal(0, "Protocol counter > 0 when nobody added one");
    await mHub.addProtocol(prot1.address);
    expect((await mHub.protocols()).length).equal(1, "Protocol not properly added");
    await mHub.addProtocol(prot2.address);
    expect((await mHub.protocols()).length).equal(2, "Protocol not properly added");
    await mHub.addProtocol(prot3.address);
    expect((await mHub.protocols()).length).equal(3, "Protocol not properly added");
    expect((await mHub.protocols())[0]).equal(prot1.address, "Protocol not properly added");
    expect((await mHub.protocols())[1]).equal(prot2.address, "Protocol not properly added");
    expect((await mHub.protocols())[2]).equal(prot3.address, "Protocol not properly added");

    return {
      hub: mHub,
      users: { admin: admin, owner: hubOwner, trader: trader, user: user },
      protocols: [prot1, prot2, prot3],
      tokens: { usdc, weth, wbtc },
      aprs: aprs,
      notInvested: notInv,
      priceFeed: pFeed,
    }
  }


  describe("Protocols", async function () {
    it("Should properly remove and add protocols", async function () {
      const { hub, users, protocols } = await loadFixture(deployMuchoHub);

      await hub.removeProtocol(protocols[1].address);
      let prots = await hub.protocols();
      expect(prots.length).equal(2, "Protocol not properly removed");
      expect(prots[0]).equal(protocols[0].address);
      expect(prots[1]).equal(protocols[2].address);

      await hub.addProtocol(protocols[1].address);
      prots = await hub.protocols();
      expect(prots.length).equal(3, "Protocol not properly added");
      expect(prots[0]).equal(protocols[0].address);
      expect(prots[1]).equal(protocols[2].address);
      expect(prots[2]).equal(protocols[1].address);
    });

  });


  describe("Default Investment", async function () {
    it("Should fail when depositing with no default protocol", async function () {
      const { hub, users, protocols, tokens } = await loadFixture(deployMuchoHub);
      const token = tokens.usdc;
      const AMOUNT = 1000 * 10 ** 6;

      await token.connect(users.user).approve(hub.address, AMOUNT);
      await expect(hub.connect(users.owner).depositFrom(users.user.address, tokens.usdc.address, AMOUNT)).revertedWith("MuchoHub: no protocol defined for the token");
    });

    it("Should fail when fixing default investment with less than 100% for a token", async function () {
      const { hub, users, protocols, tokens, aprs, notInvested, priceFeed } = await loadFixture(deployMuchoHub);
      const token = tokens.usdc;
      const PROTOCOL_INDEX = 0;

      //console.log("Investment 99%");
      let defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 9900 }];
      await expect(hub.setDefaultInvestment(token.address, defInput)).revertedWith("MuchoHub: Partition list total is not 100% of investment");

      //console.log("Investment 33 + 66.99%");
      defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 3300 },
      { protocol: protocols[PROTOCOL_INDEX].address, percentage: 6699 }];
      await expect(hub.setDefaultInvestment(token.address, defInput)).revertedWith("MuchoHub: Partition list total is not 100% of investment");

      //console.log("Investment 100%");
      defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 10000 }];
      await hub.setDefaultInvestment(token.address, defInput);

      //console.log("Investment 33.33 + 33.33 + 33.34%");
      defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 3333 },
      { protocol: protocols[PROTOCOL_INDEX].address, percentage: 3333 },
      { protocol: protocols[PROTOCOL_INDEX].address, percentage: 3334 },];
      await hub.setDefaultInvestment(token.address, defInput);

      //console.log("Investment Done");
    });

    it("Should work when depositing with default protocol with 100% share", async function () {
      const { hub, users, protocols, tokens, aprs, notInvested, priceFeed } = await loadFixture(deployMuchoHub);
      const token = tokens.weth;
      const AMOUNT = 3.1453;
      const DECIMALS = await token.decimals();
      const bnAmount = toBN(AMOUNT, DECIMALS);
      const PROTOCOL_INDEX = 0;

      //Set default input with 100% in a protocol
      const defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 10000 }];
      await hub.setDefaultInvestment(token.address, defInput);
      const def = await hub.getTokenDefaults(token.address);
      expect(def.length).equal(defInput.length, "Default investment not properly set");
      expect(def[0][0]).equal(defInput[0].protocol, "Default investment not properly set");
      expect(def[0][1]).equal(defInput[0].percentage, "Default investment not properly set");

      //Save user balance and check HUB total staked is 0 before depositing
      const previousBalance: eth.BigNumber = await token.connect(users.user).balanceOf(users.user.address);
      expect(await hub.getTotalStaked(token.address)).equal(0, "HUB balance is not 0 before depositing");
      expect(await hub.getTotalNotInvested(token.address)).equal(0, "HUB balance is not 0 before depositing");

      //Make deposit
      await token.connect(users.user).approve(hub.address, bnAmount);
      await hub.connect(users.owner).depositFrom(users.user.address, token.address, bnAmount);

      //Compare user balance and HUB total staked after depositing
      const newBalance = await token.connect(users.user).balanceOf(users.user.address);
      expect(newBalance).equal(previousBalance.sub(bnAmount), "Not expected balance in user after deposit");
      expect(await hub.getTotalNotInvested(token.address)).equal(bnAmount.mul(notInvested[PROTOCOL_INDEX]).div(10000), "Not invested amount fail");
      expect(await hub.getTotalStaked(token.address)).equal(bnAmount, "Total invested amount fail");

      //Check total USD is correct
      const totalUSD = await hub.getTotalUSD();
      const price = fromBN(await priceFeed.getPrice(token.address), 30);
      expect(totalUSD).equal(bnAmount.mul(price).mul(10 ** (18 - DECIMALS)), "Total USD does not work");

      //Check current investment is correct
      let EXPECTED_INV: any = {};
      EXPECTED_INV[protocols[PROTOCOL_INDEX].address] = bnAmount;
      const inv = await hub.getCurrentInvestment(token.address);
      expect(inv.parts.length).equal(3, "Current investment has different number of parts");
      for (var i = 0; i < inv.parts.length; i++) {

        if (!EXPECTED_INV[inv.parts[i].protocol]) {
          expect(inv.parts[i].amount).equal(0, `Not expected investment in protocol ${inv.parts[i].protocol}`);
        }
        else {
          expect(inv.parts[i].amount).equal(EXPECTED_INV[inv.parts[i].protocol], `Not expected investment amount in protocol ${inv.parts[i].protocol}`);
        }

      }
    });

    it("Should work when depositing with default protocol splitting in different protocols", async function () {
      const { hub, users, protocols, tokens, aprs, notInvested, priceFeed } = await loadFixture(deployMuchoHub);
      const token = tokens.wbtc;
      const AMOUNT = 1.31453;
      const DECIMALS = await token.decimals();
      const bnAmount = toBN(AMOUNT, DECIMALS);

      //Set default input with 100% split in 3 protocols
      const defInput = [{ protocol: protocols[0].address, percentage: 3300 },
      { protocol: protocols[1].address, percentage: 2000 },
      { protocol: protocols[2].address, percentage: 4700 }];
      await hub.setDefaultInvestment(token.address, defInput);
      const def = await hub.getTokenDefaults(token.address);
      expect(def.length).equal(defInput.length, "Default investment not properly set");
      for (var i = 0; i < def.length; i++) {
        expect(def[i][0]).equal(defInput[i].protocol, "Default investment not properly set");
        expect(def[i][1]).equal(defInput[i].percentage, "Default investment not properly set");
      }

      //Save user balance and check HUB total staked is 0 before depositing
      const previousBalance = await token.connect(users.user).balanceOf(users.user.address);
      expect(await hub.getTotalStaked(token.address)).equal(0, "HUB balance is not 0 before depositing");
      expect(await hub.getTotalNotInvested(token.address)).equal(0, "HUB balance is not 0 before depositing");

      //Make deposit
      await token.connect(users.user).approve(hub.address, bnAmount);
      await hub.connect(users.owner).depositFrom(users.user.address, token.address, bnAmount);

      //Compare user balance and HUB total staked after depositing
      const newBalance = await token.connect(users.user).balanceOf(users.user.address);
      expect(newBalance).equal(previousBalance.sub(bnAmount), "Not expected balance in user after deposit");
      let expectedNotInvested = eth.BigNumber.from(0);
      for (var i = 0; i < notInvested.length; i++) {
        expectedNotInvested = expectedNotInvested.add(bnAmount.mul(defInput[i].percentage).mul(notInvested[i]).div(100000000));
      }
      expect(await hub.getTotalNotInvested(token.address)).equal(expectedNotInvested, "Not invested amount fail");
      expect(await hub.getTotalStaked(token.address)).equal(bnAmount, "Total invested amount fail");

      //Check total USD is correct
      const totalUSD = await hub.getTotalUSD();
      const price = fromBN(await priceFeed.getPrice(token.address), 30);
      expect(totalUSD).equal(bnAmount.mul(price).mul(10 ** (18 - DECIMALS)), "Total USD does not work");

      //Check current investment is correct
      let EXPECTED_INV: any = {};
      for (var i = 0; i < defInput.length; i++) {
        EXPECTED_INV[defInput[i].protocol] = bnAmount.mul(defInput[i].percentage).div(10000);
      }
      const inv = await hub.getCurrentInvestment(token.address);
      expect(inv.parts.length).equal(3, "Current investment has different number of parts");
      for (var i = 0; i < inv.parts.length; i++) {

        if (!EXPECTED_INV[inv.parts[i].protocol]) {
          expect(inv.parts[i].amount).equal(0, `Not expected investment in protocol ${inv.parts[i].protocol}`);
        }
        else {
          expect(inv.parts[i].amount).equal(EXPECTED_INV[inv.parts[i].protocol], `Not expected investment amount in protocol ${inv.parts[i].protocol}`);
        }

      }
    });

  });

  describe("APR and deposit/withdraw", async () => {

    it("Should earn and lose APR in different protocols", async () => {
      const { hub, users, protocols, tokens, aprs, notInvested, priceFeed } = await loadFixture(deployMuchoHub);
      const token = tokens.wbtc;
      const AMOUNT = 1.31453;
      const DECIMALS = await token.decimals();
      const bnAmount = toBN(AMOUNT, DECIMALS);
      const investmentPercentages = [3300, 2000, 4700];
      const LAPSE = 33 * 24 * 3600; //33 days
      const ONE_YEAR = 365 * 24 * 3600;
      const expectedAmounts = investmentPercentages.map((v,i) => {
        return bnAmount.mul(notInvested[i]).div(10000) //Not Invested part
          .add(bnAmount.mul(10000 - notInvested[i]).div(10000)) //Initial invested part
          .add(bnAmount.mul(10000 - notInvested[i]).mul(aprs[i]).mul(LAPSE).div(ONE_YEAR).div(10000).div(10000)) //Profit invested part
          .mul(v).div(10000); //Investment part
      });
      const expectedAmount = expectedAmounts.reduce((p, c) => p.add(c), ethers.BigNumber.from(0));

      //Set default input with 100% split in 3 protocols
      const defInput = [{ protocol: protocols[0].address, percentage: investmentPercentages[0] },
                        { protocol: protocols[1].address, percentage: investmentPercentages[1] },
                        { protocol: protocols[2].address, percentage: investmentPercentages[2] }];
      await hub.setDefaultInvestment(token.address, defInput);
      const def = await hub.getTokenDefaults(token.address);

      //Make deposit
      await token.connect(users.user).approve(hub.address, bnAmount);
      await hub.connect(users.owner).depositFrom(users.user.address, token.address, bnAmount);
      const timeDeposit = await time.latest();

      //Wait and refresh with apr
      await time.setNextBlockTimestamp(timeDeposit + LAPSE);
      await hub.refreshAllInvestments();

      //Check amounts
      const total = await hub.getTotalStaked(token.address);
      const parts = await hub.getCurrentInvestment(token.address);
      expect(total).equal(expectedAmount, "Expected total amount after APR does not fit");
      expect(parts[0].length).equal(expectedAmounts.length, "Actual investment number of parts different from theoric");
      parts[0].forEach((p, i) =>{
        expect(p.amount).equal(expectedAmounts[i], `Amount not expected for protocol${i}`);
      })

      //Check not invested
      const expectedNotInvested = expectedAmounts.reduce( (p, v, i) => p.add(v.mul(notInvested[i]).div(10000)), ethers.BigNumber.from(0) );
      const notInvestedTotal = await hub.getTotalNotInvested(token.address);
      expect(notInvestedTotal).equal(expectedNotInvested, "Not invested total is not expected");

    });

    it("Should withdraw less than invested after earn and lose APR in different protocols", async () => {
      const { hub, users, protocols, tokens, aprs, notInvested, priceFeed } = await loadFixture(deployMuchoHub);
      const token = tokens.wbtc;
      const AMOUNT = 1.31453;
      const DECIMALS = await token.decimals();
      const bnAmount = toBN(AMOUNT, DECIMALS);
      const investmentPercentages = [3300, 2000, 4700];
      const LAPSE = 33 * 24 * 3600; //33 days
      const ONE_YEAR = 365 * 24 * 3600;

      //Set default input with 100% split in 3 protocols
      const defInput = [{ protocol: protocols[0].address, percentage: investmentPercentages[0] },
                        { protocol: protocols[1].address, percentage: investmentPercentages[1] },
                        { protocol: protocols[2].address, percentage: investmentPercentages[2] }];
      await hub.setDefaultInvestment(token.address, defInput);

      //Make deposit
      await token.connect(users.user).approve(hub.address, bnAmount);
      await hub.connect(users.owner).depositFrom(users.user.address, token.address, bnAmount);
      const timeDeposit = await time.latest();

      //Wait and refresh with apr
      await time.setNextBlockTimestamp(timeDeposit + LAPSE);
      await hub.refreshAllInvestments();

      //Save amounts
      const totalStakedAfterApr = await hub.getTotalStaked(token.address);
      const notInvestedTotalAfterApr = await hub.getTotalNotInvested(token.address);

      //withdraw less than not invested, should only take from the not invested liquidity
      const amountWithdraw = notInvestedTotalAfterApr.div(10);
      const balanceBeforeWithdraw = await token.balanceOf(users.user.address);
      await hub.connect(users.owner).withdrawFrom(users.user.address, token.address, amountWithdraw);
      const balanceAfterWithdraw = await token.balanceOf(users.user.address);
      const notInvestedAfterWithdraw = await hub.getTotalNotInvested(token.address);
      const totalStakedAfterWithdraw = await hub.getTotalStaked(token.address);

      expect(balanceAfterWithdraw).equal(balanceBeforeWithdraw.add(amountWithdraw), "User balance wrong after withdraw");
      expect(notInvestedAfterWithdraw).equal(notInvestedTotalAfterApr.sub(amountWithdraw), "Not invested after withdraw is wrong");
      expect(totalStakedAfterWithdraw).equal(totalStakedAfterApr.sub(amountWithdraw), "Total staked after withdraw is wrong");
    });


    it("Should withdraw MORE than invested after earn and lose APR in different protocols", async () => {
      const { hub, users, protocols, tokens, aprs, notInvested, priceFeed } = await loadFixture(deployMuchoHub);
      const token = tokens.wbtc;
      const AMOUNT = 1.31453;
      const DECIMALS = await token.decimals();
      const bnAmount = toBN(AMOUNT, DECIMALS);
      const investmentPercentages = [3300, 2000, 4700];
      const LAPSE = 33 * 24 * 3600; //33 days
      const ONE_YEAR = 365 * 24 * 3600;

      //Set default input with 100% split in 3 protocols
      const defInput = [{ protocol: protocols[0].address, percentage: investmentPercentages[0] },
                        { protocol: protocols[1].address, percentage: investmentPercentages[1] },
                        { protocol: protocols[2].address, percentage: investmentPercentages[2] }];
      await hub.setDefaultInvestment(token.address, defInput);

      //Make deposit
      await token.connect(users.user).approve(hub.address, bnAmount);
      await hub.connect(users.owner).depositFrom(users.user.address, token.address, bnAmount);
      const timeDeposit = await time.latest();

      //Wait and refresh with apr
      await time.setNextBlockTimestamp(timeDeposit + LAPSE);
      await hub.refreshAllInvestments();

      //Save amounts
      const totalStakedAfterApr = await hub.getTotalStaked(token.address);
      const notInvestedTotalAfterApr = await hub.getTotalNotInvested(token.address);

      //withdraw MORE than not invested, should only take from the not invested liquidity
      const amountWithdraw = notInvestedTotalAfterApr.add(totalStakedAfterApr.sub(notInvestedTotalAfterApr).div(2));
      const balanceBeforeWithdraw = await token.balanceOf(users.user.address);
      await hub.connect(users.owner).withdrawFrom(users.user.address, token.address, amountWithdraw);
      const balanceAfterWithdraw = await token.balanceOf(users.user.address);
      const notInvestedAfterWithdraw = await hub.getTotalNotInvested(token.address);
      const totalStakedAfterWithdraw = await hub.getTotalStaked(token.address);

      expect(balanceAfterWithdraw).equal(balanceBeforeWithdraw.add(amountWithdraw), "User balance wrong after withdraw");
      expect(notInvestedAfterWithdraw).equal(0, "Not invested after withdraw is wrong");
      expect(totalStakedAfterWithdraw).equal(totalStakedAfterApr.sub(amountWithdraw), "Total staked after withdraw is wrong");
    });

  });

  describe("Move liquidity",async () => {
    it("Should be able to move liquidity among protocols", async () => {
      const { hub, users, protocols, tokens, aprs, notInvested, priceFeed } = await loadFixture(deployMuchoHub);
      const token = tokens.wbtc;
      const AMOUNT = 1.31453;
      const DECIMALS = await token.decimals();
      const bnAmount = toBN(AMOUNT, DECIMALS);
      const investmentPercentages = [3300, 2000, 4700];
      const LAPSE = 33 * 24 * 3600; //33 days
      const ONE_YEAR = 365 * 24 * 3600;

      //Set default input with 100% split in 3 protocols
      const defInput = [{ protocol: protocols[0].address, percentage: investmentPercentages[0] },
                        { protocol: protocols[1].address, percentage: investmentPercentages[1] },
                        { protocol: protocols[2].address, percentage: investmentPercentages[2] }];
      await hub.setDefaultInvestment(token.address, defInput);

      //Make deposit
      await token.connect(users.user).approve(hub.address, bnAmount);
      await hub.connect(users.owner).depositFrom(users.user.address, token.address, bnAmount);
      const timeDeposit = await time.latest();

      //Wait and refresh with apr
      await time.setNextBlockTimestamp(timeDeposit + LAPSE);
      await hub.refreshAllInvestments();

      //Save amounts
      const totalStakedAfterApr = await hub.getTotalStaked(token.address);
      const notInvestedTotalAfterApr = await hub.getTotalNotInvested(token.address);
      const [amounts,] = await hub.getCurrentInvestment(token.address);

      //Test fails when moving more than staked
      await expect(hub.connect(users.trader).moveInvestment(token.address, amounts[0].amount.add(1), protocols[0].address, protocols[1].address))
              .revertedWith("MuchoHub: Cannot move more than staked");
      
      //Test moves right
      await hub.connect(users.trader).moveInvestment(token.address, amounts[0].amount, protocols[0].address, protocols[2].address);
      const [amountsAfterMove,] = await hub.getCurrentInvestment(token.address);
      expect(amountsAfterMove[0].amount).equal(0);
      expect(amountsAfterMove[1].amount).equal(amounts[1].amount);
      expect(amountsAfterMove[2].amount).equal(amounts[0].amount.add(amounts[2].amount));

      const secondMove = amountsAfterMove[1].amount.div(2);
      await hub.connect(users.trader).moveInvestment(token.address, secondMove, protocols[1].address, protocols[0].address);
      const [amountsAfterSecMove,] = await hub.getCurrentInvestment(token.address);
      expect(amountsAfterSecMove[0].amount).equal(secondMove);
      expect(amountsAfterSecMove[1].amount).equal(amountsAfterMove[1].amount.sub(secondMove));
      expect(amountsAfterSecMove[2].amount).equal(amountsAfterMove[2].amount);

    });
  });


  describe("Roles", async () => {
    it("Should only work with proper roles", async () => {
      const { hub, users, protocols, tokens, aprs, notInvested, priceFeed } = await loadFixture(deployMuchoHub);

      //ADMIN functions
      const ONLY_ADMIN_REASON = "MuchoRoles: Only for admin";
      const FAKE_ADDRESS = hub.address;
      await expect(hub.connect(users.user).addProtocol(FAKE_ADDRESS)).revertedWith(ONLY_ADMIN_REASON);
      await expect(hub.connect(users.owner).addProtocol(FAKE_ADDRESS)).revertedWith(ONLY_ADMIN_REASON);
      await expect(hub.connect(users.trader).addProtocol(FAKE_ADDRESS)).revertedWith(ONLY_ADMIN_REASON);

      await expect(hub.connect(users.user).removeProtocol(FAKE_ADDRESS)).revertedWith(ONLY_ADMIN_REASON);
      await expect(hub.connect(users.owner).removeProtocol(FAKE_ADDRESS)).revertedWith(ONLY_ADMIN_REASON);
      await expect(hub.connect(users.trader).removeProtocol(FAKE_ADDRESS)).revertedWith(ONLY_ADMIN_REASON);


      //TRADER OR ADMIN
      const ONLY_TRADER_OR_ADMIN_REASON = "MuchoRoles: Only for trader or admin";
      await expect(hub.connect(users.user).setDefaultInvestment(FAKE_ADDRESS, [])).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(hub.connect(users.owner).setDefaultInvestment(FAKE_ADDRESS, [])).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);

      await expect(hub.connect(users.user).moveInvestment(FAKE_ADDRESS, 1E6, FAKE_ADDRESS, FAKE_ADDRESS)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(hub.connect(users.owner).moveInvestment(FAKE_ADDRESS, 1E6, FAKE_ADDRESS, FAKE_ADDRESS)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);

      await expect(hub.connect(users.user).refreshInvestment(FAKE_ADDRESS)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(hub.connect(users.owner).refreshInvestment(FAKE_ADDRESS)).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);

      await expect(hub.connect(users.user).refreshAllInvestments()).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);
      await expect(hub.connect(users.owner).refreshAllInvestments()).revertedWith(ONLY_TRADER_OR_ADMIN_REASON);


      //OWNER (contract owner)
      const ONLY_OWNER_REASON = "Ownable: caller is not the owner";
      await expect(hub.connect(users.user).depositFrom(FAKE_ADDRESS, FAKE_ADDRESS, 1E6)).revertedWith(ONLY_OWNER_REASON);
      await expect(hub.connect(users.trader).depositFrom(FAKE_ADDRESS, FAKE_ADDRESS, 1E6)).revertedWith(ONLY_OWNER_REASON);
      await expect(hub.connect(users.admin).depositFrom(FAKE_ADDRESS, FAKE_ADDRESS, 1E6)).revertedWith(ONLY_OWNER_REASON);

      await expect(hub.connect(users.user).withdrawFrom(FAKE_ADDRESS, FAKE_ADDRESS, 1E6)).revertedWith(ONLY_OWNER_REASON);
      await expect(hub.connect(users.trader).withdrawFrom(FAKE_ADDRESS, FAKE_ADDRESS, 1E6)).revertedWith(ONLY_OWNER_REASON);
      await expect(hub.connect(users.admin).withdrawFrom(FAKE_ADDRESS, FAKE_ADDRESS, 1E6)).revertedWith(ONLY_OWNER_REASON);

    });
  });

});
