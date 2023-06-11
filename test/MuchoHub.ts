import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MuchoHubMock, PriceFeedMock } from "../typechain-types";
import { BigNumber } from "bignumber.js";
import { formatBytes32String } from "ethers/lib/utils";
import { ethers as eth } from "ethers";
import { InvestmentPartStruct } from "../typechain-types/contracts/MuchoHub";


describe("MuchoHubTest", async function () {

  const toBN = (num: Number, dec: Number): eth.BigNumber => {
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
    const [admin, hubOwner, trader, user] = await ethers.getSigners();

    //Deploy ERC20 fakes
    const usdc = await deployContract("USDC");
    const weth = await deployContract("WETH");
    const wbtc = await deployContract("WBTC");
    await usdc.mint(user.address, toBN(100000, 6));
    await weth.mint(user.address, toBN(100, 18));
    await wbtc.mint(user.address, toBN(10, 12));

    //Deploy rest of mocks
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
    await mHub.grantRole(formatBytes32String("0"), admin.address);
    await mHub.grantRole(formatBytes32String("TRADER"), trader.address);
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

      console.log("Investment 99%");
      let defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 9900 }];
      await expect(hub.setDefaultInvestment(token.address, defInput)).revertedWith("MuchoHub: Partition list total is not 100% of investment");

      console.log("Investment 33 + 66.99%");
      defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 3300 },
      { protocol: protocols[PROTOCOL_INDEX].address, percentage: 6699 }];
      await expect(hub.setDefaultInvestment(token.address, defInput)).revertedWith("MuchoHub: Partition list total is not 100% of investment");

      console.log("Investment 100%");
      defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 10000 }];
      await hub.setDefaultInvestment(token.address, defInput);

      console.log("Investment 33.33 + 33.33 + 33.34%");
      defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 3333 },
      { protocol: protocols[PROTOCOL_INDEX].address, percentage: 3333 },
      { protocol: protocols[PROTOCOL_INDEX].address, percentage: 3334 },];
      await hub.setDefaultInvestment(token.address, defInput);

      console.log("Investment Done");
    });

    it("Should work when depositing with default protocol with 100% share", async function () {
      const { hub, users, protocols, tokens, aprs, notInvested, priceFeed } = await loadFixture(deployMuchoHub);
      const token = tokens.usdc;
      const AMOUNT = 1000 * 10 ** 6;
      const PROTOCOL_INDEX = 0;

      //Set default input with 100% in a protocol
      const defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 10000 }];
      await hub.setDefaultInvestment(token.address, defInput);
      const def = await hub.getTokenDefaults(token.address);
      expect(def.length).equal(defInput.length, "Default investment not properly set");
      expect(def[0][0]).equal(defInput[0].protocol, "Default investment not properly set");
      expect(def[0][1]).equal(defInput[0].percentage, "Default investment not properly set");

      //Save user balance and check HUB total staked is 0 before depositing
      const previousBalance = await token.connect(users.user).balanceOf(users.user.address);
      expect(await hub.getTotalStaked(token.address)).equal(0, "HUB balance is not 0 before depositing");
      expect(await hub.getTotalNotInvested(token.address)).equal(0, "HUB balance is not 0 before depositing");

      //Make deposit
      await token.connect(users.user).approve(hub.address, AMOUNT);
      await hub.connect(users.owner).depositFrom(users.user.address, tokens.usdc.address, AMOUNT);

      //Compare user balance and HUB total staked after depositing
      const newBalance = await token.connect(users.user).balanceOf(users.user.address);
      expect(newBalance).equal(previousBalance - AMOUNT, "Not expected balance in user after deposit");
      expect(await hub.getTotalNotInvested(token.address)).equal(AMOUNT * notInvested[PROTOCOL_INDEX] / 10000, "Not invested amount fail");
      expect(await hub.getTotalStaked(token.address)).equal(AMOUNT, "Total invested amount fail");

      //Check total USD is correct
      const [totalUSD, listUSD] = await hub.getTotalUSDAndList();
      const price = fromBN(await priceFeed.getPrice(token.address), 30);
      expect(totalUSD).equal(Math.round(AMOUNT * price), "Total USD does not work");
    });

    it("Should work when depositing with default protocol splitting in different protocols", async function () {
      const { hub, users, protocols, tokens, aprs, notInvested, priceFeed } = await loadFixture(deployMuchoHub);
      const token = tokens.usdc;
      const AMOUNT = 1000 * 10 ** 6;
      const PROTOCOL_INDEX = 0;

      //Set default input with 100% in a protocol
      const defInput = [{ protocol: protocols[PROTOCOL_INDEX].address, percentage: 10000 }];
      await hub.setDefaultInvestment(token.address, defInput);
      const def = await hub.getTokenDefaults(token.address);
      expect(def.length).equal(defInput.length, "Default investment not properly set");
      expect(def[0][0]).equal(defInput[0].protocol, "Default investment not properly set");
      expect(def[0][1]).equal(defInput[0].percentage, "Default investment not properly set");

      //Save user balance and check HUB total staked is 0 before depositing
      const previousBalance = await token.connect(users.user).balanceOf(users.user.address);
      expect(await hub.getTotalStaked(token.address)).equal(0, "HUB balance is not 0 before depositing");
      expect(await hub.getTotalNotInvested(token.address)).equal(0, "HUB balance is not 0 before depositing");

      //Make deposit
      await token.connect(users.user).approve(hub.address, AMOUNT);
      await hub.connect(users.owner).depositFrom(users.user.address, tokens.usdc.address, AMOUNT);

      //Compare user balance and HUB total staked after depositing
      const newBalance = await token.connect(users.user).balanceOf(users.user.address);
      expect(newBalance).equal(previousBalance - AMOUNT, "Not expected balance in user after deposit");
      expect(await hub.getTotalNotInvested(token.address)).equal(AMOUNT * notInvested[PROTOCOL_INDEX] / 10000, "Not invested amount fail");
      expect(await hub.getTotalStaked(token.address)).equal(AMOUNT, "Total invested amount fail");

      //Check total USD is correct
      const [totalUSD, listUSD] = await hub.getTotalUSDAndList();
      const price = fromBN(await priceFeed.getPrice(token.address), 30);
      expect(totalUSD).equal(Math.round(AMOUNT * price), "Total USD does not work");
    });

  });

});
