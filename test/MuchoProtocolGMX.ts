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
  async function deployMuchoGMX() {
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
    await glpPriceFeed.addToken(usdt.address, toBN(1, 30));
    await glpPriceFeed.addToken(dai.address, toBN(1, 30));
    await glpVault.setPriceFeed(glpPriceFeed.address);
    const glpRRct = await ethers.getContractFactory("GLPRewardRouterMock");
    const glpRewardRouter = await glpRRct.deploy(glp.address, glpPriceFeed.address, weth.address);
    const glpRouter = await (await ethers.getContractFactory("GLPRouterMock")).deploy(glpVault.address, glp.address, usdc.address, weth.address, wbtc.address);

    //Reward router
    const mRewardRouter = await (await ethers.getContractFactory("MuchoRewardRouter")).deploy();

    //Deploy main contract
    const mMuchoGMX = await (await ethers.getContractFactory("MuchoProtocolGMX")).connect(owner).deploy();

    //set contracts:
    await mMuchoGMX.updatefsGLP(glp.address);
    expect(await mMuchoGMX.fsGLP()).equal(glp.address);

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

    await mMuchoGMX.setCompoundProtocol(mMuchoGMX.address); //autocompound
    expect(await mMuchoGMX.compoundProtocol()).equal(mMuchoGMX.address);
    
    //Set ownerships
    const TRADER_ROLE = await mMuchoGMX.TRADER();
    const ADMIN_ROLE = await mMuchoGMX.DEFAULT_ADMIN_ROLE();
    await mMuchoGMX.grantRole(ADMIN_ROLE, admin.address);
    await mMuchoGMX.grantRole(TRADER_ROLE, trader.address);
    await mMuchoGMX.transferOwnership(owner.address);

    //Add tokens
    await mMuchoGMX.addToken(usdc.address);
    await mMuchoGMX.addToken(weth.address);
    await mMuchoGMX.addToken(wbtc.address);
    await mMuchoGMX.addSecondaryToken(usdc.address, usdt.address);
    await mMuchoGMX.addSecondaryToken(usdc.address, dai.address);

    //Set parameters
    const APR_UPDATE_PERIOD = 24*3600;
    await mMuchoGMX.setAprUpdatePeriod(APR_UPDATE_PERIOD);
    expect(await mMuchoGMX.aprUpdatePeriod()).equal(APR_UPDATE_PERIOD);

    const SLIPPAGE = 10;
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
    const rwSplit:RewardSplitStruct = {ownerPercentage:OWNER_PERCENTAGE, NftPercentage:NFT_PERCENTAGE}
    await mMuchoGMX.setRewardPercentages(rwSplit);
    expect((await mMuchoGMX.rewardSplit()).ownerPercentage).equal(OWNER_PERCENTAGE);
    expect((await mMuchoGMX.rewardSplit()).NftPercentage).equal(NFT_PERCENTAGE);



    return {
      mMuchoGMX: mMuchoGMX,
      users: { admin: admin, owner: owner, trader: trader, user: user },
      glpVault: glpVault,
      glpPriceFeed : glpPriceFeed,
      glpRewardRouter : glpRewardRouter,
      glpRouter : glpRouter,
      mRewardRouter : mRewardRouter,
      tokens: { usdc, weth, wbtc, usdt, dai },
      glpToken: glp,
      constants: {APR_UPDATE_PERIOD, SLIPPAGE, MIN_NOTINV_PCTG, DES_NOTINV_PCTG, MIN_WEIGHT_MOVE, CLAIM_ESGMX, MANUAL_WEIGHTS, OWNER_PERCENTAGE, NFT_PERCENTAGE},
    }
  }


  describe("Weights", async function () {
    it("Read weights from GLP", async function () {
      const { mMuchoGMX, users, glpVault, glpPriceFeed, glpRewardRouter, glpRouter, 
        mRewardRouter, tokens, glpToken} = await loadFixture(deployMuchoGMX);

        const WETH_PRICE = await glpPriceFeed.getPrice(tokens.weth.address);
        const WBTC_PRICE = await glpPriceFeed.getPrice(tokens.wbtc.address);
        const GLP_AMOUNTS = {
          usdc: toBN(1000, 6),
          usdt: toBN(100, 6),
          dai: toBN(200, 6),
          weth: toBN(600, 18+30).div(WETH_PRICE),
          wbtc: toBN(400, 12+30).div(WBTC_PRICE),
        };
        const EXPECTED_WEIGHTS = {
          usdc: 1300/2300,
          weth: 600/2300,
          wbtc: 400/2300,
        }
        await tokens.usdc.mint(glpVault.address, GLP_AMOUNTS.usdc);
        await tokens.usdt.mint(glpVault.address, GLP_AMOUNTS.usdt);
        await tokens.dai.mint(glpVault.address, GLP_AMOUNTS.dai);
        await tokens.weth.mint(glpVault.address, GLP_AMOUNTS.weth);
        await tokens.wbtc.mint(glpVault.address, GLP_AMOUNTS.wbtc);

        //Test reads glp weights properly
        await mMuchoGMX.connect(users.admin).updateGlpWeights();
        expect(await mMuchoGMX.getTokenWeight(tokens.usdc.address)).closeTo(toBN(EXPECTED_WEIGHTS.usdc, 4), 1);
        expect(await mMuchoGMX.getTokenWeight(tokens.weth.address)).closeTo(toBN(EXPECTED_WEIGHTS.weth, 4), 1);
        expect(await mMuchoGMX.getTokenWeight(tokens.wbtc.address)).closeTo(toBN(EXPECTED_WEIGHTS.wbtc, 4), 1);

        //Transfer to vaults
        const AMOUNTS = {
          usdc: toBN(300, 6),
          weth: toBN(300, 18+30).div(WETH_PRICE),
          wbtc: toBN(300, 12+30).div(WBTC_PRICE),
        };
        await tokens.usdc.mint(mMuchoGMX.address, AMOUNTS.usdc);
        await mMuchoGMX.connect(users.owner).notifyDeposit(tokens.usdc.address, AMOUNTS.usdc);
        await tokens.weth.mint(mMuchoGMX.address, AMOUNTS.weth);
        await mMuchoGMX.connect(users.owner).notifyDeposit(tokens.weth.address, AMOUNTS.weth);
        await tokens.wbtc.mint(mMuchoGMX.address, AMOUNTS.wbtc);
        await mMuchoGMX.connect(users.owner).notifyDeposit(tokens.wbtc.address, AMOUNTS.wbtc);

        //Update to weights
        await mMuchoGMX.connect(users.owner).refreshInvestment();
    });

  });

});
