import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MuchoHubMock, PriceFeedMock } from "../typechain-types";
import { BigNumber } from "bignumber.js";
import { formatBytes32String } from "ethers/lib/utils";
import { ethers as eth, ethers } from "ethers";
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
    const APR_UPDATE_PERIOD = 24 * 3600;
    await mMuchoGMX.setAprUpdatePeriod(APR_UPDATE_PERIOD);
    expect(await mMuchoGMX.aprUpdatePeriod()).equal(APR_UPDATE_PERIOD);

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
    const rwSplit: RewardSplitStruct = { ownerPercentage: OWNER_PERCENTAGE, NftPercentage: NFT_PERCENTAGE }
    await mMuchoGMX.setRewardPercentages(rwSplit);
    expect((await mMuchoGMX.rewardSplit()).ownerPercentage).equal(OWNER_PERCENTAGE);
    expect((await mMuchoGMX.rewardSplit()).NftPercentage).equal(NFT_PERCENTAGE);



    return {
      mMuchoGMX: mMuchoGMX,
      users: { admin: admin, owner: owner, trader: trader, user: user },
      glpVault: glpVault,
      glpPriceFeed: glpPriceFeed,
      glpRewardRouter: glpRewardRouter,
      glpRouter: glpRouter,
      mRewardRouter: mRewardRouter,
      tokens: { usdc, weth, wbtc, usdt, dai },
      glpToken: glp,
      constants: { APR_UPDATE_PERIOD, SLIPPAGE, MIN_NOTINV_PCTG, DES_NOTINV_PCTG, MIN_WEIGHT_MOVE, CLAIM_ESGMX, MANUAL_WEIGHTS, OWNER_PERCENTAGE, NFT_PERCENTAGE },
    }
  }


  describe("Weights", async function () {
    
    it("Read weights from GLP", async function () {
      const { mMuchoGMX, users, glpVault, glpPriceFeed, glpRewardRouter, glpRouter,
        mRewardRouter, tokens, glpToken } = await loadFixture(deployMuchoGMX);

      interface AmountsBN {
        usdc: eth.BigNumber, usdt: eth.BigNumber, dai: eth.BigNumber, weth: eth.BigNumber, wbtc: eth.BigNumber
      }
      interface ExpectedWeights {
        usdc: number, weth: number, wbtc: number
      }
      interface ExpectedAmounts {
        usdc: { precision: number, staked: number, invested: number, notInvested: number },
        weth: { precision: number, staked: number, invested: number, notInvested: number },
        wbtc: { precision: number, staked: number, invested: number, notInvested: number },
      }

      const WETH_PRICE = await glpPriceFeed.getPrice(tokens.weth.address);
      const WBTC_PRICE = await glpPriceFeed.getPrice(tokens.wbtc.address);

      const TestWeightAndRefresh = async (GLP_AMOUNT: eth.BigNumber,
        GLP_AMOUNTS: AmountsBN,
        DEPOSIT_AMOUNTS: AmountsBN,
        EXPECTED_WEIGHTS: ExpectedWeights,
        EXPECTED_USD: ExpectedAmounts,
        EXPECTED_AMOUNTS: ExpectedAmounts) => {

        console.log("*****Start test*********");

        //Mint or burn ERC20 tokens for having in GLP Vault the exact amount requested
        for(const token in tokens){
          const bal:eth.BigNumber = await tokens[token].balanceOf(glpVault.address);
          const newAm:eth.BigNumber = GLP_AMOUNTS[token];
          if(bal.lt(newAm)){
            console.log(`Minting amount ${newAm.sub(bal)} for token ${token}`)
            await tokens[token].mint(glpVault.address, newAm.sub(bal));
          }
          else if(newAm.lt(bal)){
            console.log(`Burning amount ${bal.sub(newAm)} for token ${token}`)
            await tokens[token].burn(glpVault.address, bal.sub(newAm));
          }
          else{
            console.log(`Nothing to burn or mint for token ${token}`)
          }
        }

        //Getting GLP supply desired
        const glpBal:eth.BigNumber = await glpToken.balanceOf(glpVault.address);
        if(glpBal.lt(GLP_AMOUNT))
          await glpToken.mint(glpVault.address, GLP_AMOUNT.sub(glpBal));
        else if(glpBal.gt(GLP_AMOUNT))
          await glpToken.burn(glpVault.address, glpBal.sub(GLP_AMOUNT));

        console.log("Supply glp", await glpToken.totalSupply());
        console.log("Price glp", fromBN(await glpPriceFeed.getGLPprice(), 30));

        //Test reads glp weights properly
        await mMuchoGMX.connect(users.admin).updateGlpWeights();
        expect(await mMuchoGMX.getTokenWeight(tokens.usdc.address)).equal(toBN(EXPECTED_WEIGHTS.usdc, 4));
        expect(await mMuchoGMX.getTokenWeight(tokens.weth.address)).equal(toBN(EXPECTED_WEIGHTS.weth, 4));
        expect(await mMuchoGMX.getTokenWeight(tokens.wbtc.address)).equal(toBN(EXPECTED_WEIGHTS.wbtc, 4));

        //Depositing or withdrawing tokens in vaults
        for(const itk in tokens){
          const bal:eth.BigNumber = await mMuchoGMX.connect(users.owner).getTokenStaked(tokens[itk].address);
          const dec:number = await tokens[itk].decimals();
          console.log(`Balance in MuchoVault ${itk}: ${fromBN(bal, dec)}`);
          const newAm:eth.BigNumber = DEPOSIT_AMOUNTS[itk];
          if(bal.lt(newAm)){
            console.log(`Depositing amount ${newAm.sub(bal)} for token ${itk}`);
            await tokens[itk].mint(mMuchoGMX.address, newAm.sub(bal));
            await mMuchoGMX.connect(users.owner).notifyDeposit(tokens[itk].address, newAm.sub(bal));
          }
          else if(newAm.lt(bal)){
            const toWdr = bal.sub(newAm);
            console.log(`Withdrawing amount ${toWdr} for token ${itk}`)
            const txWdr = await mMuchoGMX.connect(users.owner).notInvestedTrySend(tokens[itk].address, toWdr, users.user.address);
            const rc = await txWdr.wait();
            const wdr = rc.events.find(e => e.event === 'WithdrawnNotInvested').args[2];
            console.log(`Withdrawn from not invested: ${wdr} for token ${itk}`)

            if(wdr.lt(toWdr)){
              const wdrInv = toWdr.sub(wdr);
              console.log(`Withdrawing from investment amount ${wdrInv} for token ${itk}`)
              await mMuchoGMX.connect(users.owner).withdrawAndSend(tokens[itk].address, wdrInv, users.user.address);
            }
          }
          else{
            console.log(`Nothing to withdraw or deposit for token ${itk}`)
          }

          const nbal:eth.BigNumber = await mMuchoGMX.connect(users.owner).getTokenStaked(tokens[itk].address);
          const ninv:eth.BigNumber = await mMuchoGMX.connect(users.owner).getTokenInvested(tokens[itk].address);
          const nninv:eth.BigNumber = await mMuchoGMX.connect(users.owner).getTokenNotInvested(tokens[itk].address);
          console.log(`FINAL Balance in MuchoVault ${itk} (${tokens[itk].address}): ${fromBN(nbal, dec)}, invested ${fromBN(ninv, dec)}, not investesd ${fromBN(nninv, dec)}`);

          const nubal:eth.BigNumber = await mMuchoGMX.connect(users.owner).getTokenUSDStaked(tokens[itk].address);
          const nuinv:eth.BigNumber = await mMuchoGMX.connect(users.owner).getTokenUSDInvested(tokens[itk].address);
          const nuninv:eth.BigNumber = await mMuchoGMX.connect(users.owner).getTokenUSDNotInvested(tokens[itk].address);
          console.log(`FINAL USD Balance in MuchoVault ${itk} (${tokens[itk].address}): ${fromBN(nubal, 18)}, invested ${fromBN(nuinv, 18)}, not investesd ${fromBN(nuninv, 18)}`);

          const usdcBal = await mMuchoGMX.connect(users.owner).getTokenStaked(tokens.usdc.address);
          console.log(`SEMI-FINAL USDC Balance in MuchoVault (${tokens.usdc.address}): ${fromBN(usdcBal, 6)}`);
        }

        const usdcBal = await mMuchoGMX.connect(users.owner).getTokenStaked(tokens.usdc.address);
        console.log(`FINAL USDC Balance in MuchoVault: ${fromBN(usdcBal, 6)}`);

        //Update to weights
        await mMuchoGMX.connect(users.owner).refreshInvestment();

        const usdcTot = await mMuchoGMX.connect(users.user).getTokenStaked(tokens.usdc.address);
        const usdcInv = await mMuchoGMX.connect(users.user).getTokenInvested(tokens.usdc.address);
        const usdcNInv = await mMuchoGMX.connect(users.user).getTokenNotInvested(tokens.usdc.address);

        const wethTot = await mMuchoGMX.connect(users.user).getTokenStaked(tokens.weth.address);
        const wethInv = await mMuchoGMX.connect(users.user).getTokenInvested(tokens.weth.address);
        const wethNInv = await mMuchoGMX.connect(users.user).getTokenNotInvested(tokens.weth.address);

        const wbtcTot = await mMuchoGMX.connect(users.user).getTokenStaked(tokens.wbtc.address);
        const wbtcInv = await mMuchoGMX.connect(users.user).getTokenInvested(tokens.wbtc.address);
        const wbtcNInv = await mMuchoGMX.connect(users.user).getTokenNotInvested(tokens.wbtc.address);

        /*console.log("TOT - INV - NOT INV");
        console.log("USDC: ", fromBN(usdcTot, 6), fromBN(usdcInv, 6), fromBN(usdcNInv, 6));
        console.log("WETH: ", fromBN(wethTot, 18), fromBN(wethInv, 18), fromBN(wethNInv, 18));
        console.log("WBTC: ", fromBN(wbtcTot, 12), fromBN(wbtcInv, 12), fromBN(wbtcNInv, 12));*/

        expect(Math.round(fromBN(usdcTot, 6 - EXPECTED_AMOUNTS.usdc.precision)) / (10 ** EXPECTED_AMOUNTS.usdc.precision)).equal(EXPECTED_AMOUNTS.usdc.staked, "Total USDC staked does not match");
        expect(Math.round(fromBN(usdcInv, 6 - EXPECTED_AMOUNTS.usdc.precision)) / (10 ** EXPECTED_AMOUNTS.usdc.precision)).equal(EXPECTED_AMOUNTS.usdc.invested, "Invested USDC staked does not match");
        expect(Math.round(fromBN(usdcNInv, 6 - EXPECTED_AMOUNTS.usdc.precision)) / (10 ** EXPECTED_AMOUNTS.usdc.precision)).equal(EXPECTED_AMOUNTS.usdc.notInvested, "Not invested USDC staked does not match");

        expect(Math.round(fromBN(wethTot, 18 - EXPECTED_AMOUNTS.weth.precision)) / (10 ** EXPECTED_AMOUNTS.weth.precision)).equal(EXPECTED_AMOUNTS.weth.staked, "Total WETH staked does not match");
        expect(Math.round(fromBN(wethInv, 18 - EXPECTED_AMOUNTS.weth.precision)) / (10 ** EXPECTED_AMOUNTS.weth.precision)).equal(EXPECTED_AMOUNTS.weth.invested, "Invested WETH staked does not match");
        expect(Math.round(fromBN(wethNInv, 18 - EXPECTED_AMOUNTS.weth.precision)) / (10 ** EXPECTED_AMOUNTS.weth.precision)).equal(EXPECTED_AMOUNTS.weth.notInvested, "Not invested WETH staked does not match");

        expect(Math.round(fromBN(wbtcTot, 12 - EXPECTED_AMOUNTS.wbtc.precision)) / (10 ** EXPECTED_AMOUNTS.wbtc.precision)).equal(EXPECTED_AMOUNTS.wbtc.staked, "Total WBTC staked does not match");
        expect(Math.round(fromBN(wbtcInv, 12 - EXPECTED_AMOUNTS.wbtc.precision)) / (10 ** EXPECTED_AMOUNTS.wbtc.precision)).equal(EXPECTED_AMOUNTS.wbtc.invested, "Invested WBTC staked does not match");
        expect(Math.round(fromBN(wbtcNInv, 12 - EXPECTED_AMOUNTS.wbtc.precision)) / (10 ** EXPECTED_AMOUNTS.wbtc.precision)).equal(EXPECTED_AMOUNTS.wbtc.notInvested, "Not invested WBTC staked does not match");

        const usdUsdcTot = await mMuchoGMX.connect(users.user).getTokenUSDStaked(tokens.usdc.address);
        const usdUsdcInv = await mMuchoGMX.connect(users.user).getTokenUSDInvested(tokens.usdc.address);
        const usdUsdcNInv = await mMuchoGMX.connect(users.user).getTokenUSDNotInvested(tokens.usdc.address);

        const usdWethTot = await mMuchoGMX.connect(users.user).getTokenUSDStaked(tokens.weth.address);
        const usdWethInv = await mMuchoGMX.connect(users.user).getTokenUSDInvested(tokens.weth.address);
        const usdWethNInv = await mMuchoGMX.connect(users.user).getTokenUSDNotInvested(tokens.weth.address);

        const usdWbtcTot = await mMuchoGMX.connect(users.user).getTokenUSDStaked(tokens.wbtc.address);
        const usdWbtcInv = await mMuchoGMX.connect(users.user).getTokenUSDInvested(tokens.wbtc.address);
        const usdWbtcNInv = await mMuchoGMX.connect(users.user).getTokenUSDNotInvested(tokens.wbtc.address);

        expect(Math.round(fromBN(usdUsdcTot, 18 - EXPECTED_USD.usdc.precision)) / (10 ** EXPECTED_USD.usdc.precision)).equal(EXPECTED_USD.usdc.staked, "Total USDC staked does not match");
        expect(Math.round(fromBN(usdUsdcInv, 18 - EXPECTED_USD.usdc.precision)) / (10 ** EXPECTED_USD.usdc.precision)).equal(EXPECTED_USD.usdc.invested, "Invested USDC staked does not match");
        expect(Math.round(fromBN(usdUsdcNInv, 18 - EXPECTED_USD.usdc.precision)) / (10 ** EXPECTED_USD.usdc.precision)).equal(EXPECTED_USD.usdc.notInvested, "Not invested USDC staked does not match");

        expect(Math.round(fromBN(usdWethTot, 18 - EXPECTED_USD.weth.precision)) / (10 ** EXPECTED_USD.weth.precision)).equal(EXPECTED_USD.weth.staked, "Total WETH staked does not match");
        expect(Math.round(fromBN(usdWethInv, 18 - EXPECTED_USD.weth.precision)) / (10 ** EXPECTED_USD.weth.precision)).equal(EXPECTED_USD.weth.invested, "Invested WETH staked does not match");
        expect(Math.round(fromBN(usdWethNInv, 18 - EXPECTED_USD.weth.precision)) / (10 ** EXPECTED_USD.weth.precision)).equal(EXPECTED_USD.weth.notInvested, "Not invested WETH staked does not match");

        expect(Math.round(fromBN(usdWbtcTot, 18 - EXPECTED_USD.wbtc.precision)) / (10 ** EXPECTED_USD.wbtc.precision)).equal(EXPECTED_USD.wbtc.staked, "Total WBTC staked does not match");
        expect(Math.round(fromBN(usdWbtcInv, 18 - EXPECTED_USD.wbtc.precision)) / (10 ** EXPECTED_USD.wbtc.precision)).equal(EXPECTED_USD.wbtc.invested, "Invested WBTC staked does not match");
        expect(Math.round(fromBN(usdWbtcNInv, 18 - EXPECTED_USD.wbtc.precision)) / (10 ** EXPECTED_USD.wbtc.precision)).equal(EXPECTED_USD.wbtc.notInvested, "Not invested WBTC staked does not match");


        /*console.log("(USD) TOT - INV - NOT INV");
        console.log("usd USDC: ", fromBN(usdUsdcTot, 18), fromBN(usdUsdcInv, 18), fromBN(usdUsdcNInv, 18));
        console.log("usd WETH: ", fromBN(usdWethTot, 18), fromBN(usdWethInv, 18), fromBN(usdWethNInv, 18));
        console.log("usd WBTC: ", fromBN(usdWbtcTot, 18), fromBN(usdWbtcInv, 18), fromBN(usdWbtcNInv, 18));
 
        console.log("Price glp", fromBN(await glpPriceFeed.getGLPprice(), 30));
        console.log("Amount glp", fromBN(await glpToken.balanceOf(mMuchoGMX.address), 18));
        console.log("Decimals glp", await glpToken.decimals());*/
      }

      //Test Values: https://docs.google.com/spreadsheets/d/1OBsrnXMI5orVMv7alr9ZSxZ4F0rT6xvfJxqut-F71yY/edit#gid=1507133984
      await TestWeightAndRefresh(toBN(2500, 18),
        {
          usdc: toBN(1000*1e6, 6),
          usdt: toBN(300*1e6, 6),
          dai: toBN(200*1e6, 6),
          weth: toBN(600*1e6, 18 + 30).div(WETH_PRICE),
          wbtc: toBN(300*1e6, 12 + 30).div(WBTC_PRICE),
        }
        ,
        {
          usdc: toBN(300, 6),
          usdt: toBN(0, 6),
          dai: toBN(0, 6),
          weth: toBN(300, 18 + 30).div(WETH_PRICE),
          wbtc: toBN(300, 12 + 30).div(WBTC_PRICE),
        },
        {
          usdc: 1500 / 2400,
          weth: 600 / 2400,
          wbtc: 300 / 2400,
        }
        ,
        {
          usdc: { precision: 4, staked: 299.2725, invested: 290.2725, notInvested: 9 },
          weth: { precision: 4, staked: 299.7090, invested: 116.1090, notInvested: 183.60 },
          wbtc: { precision: 4, staked: 299.8545, invested: 58.0545, notInvested: 241.80 },
        }
        ,
        {
          usdc: { precision: 4, staked: 299.2725, invested: 290.2725, notInvested: 9 },
          weth: { precision: 6, staked: 0.187318, invested: 0.072568, notInvested: 0.114750 },
          wbtc: { precision: 7, staked: 0.0124939, invested: 0.0024189, notInvested: 0.0100750 },
        }
      );

      await TestWeightAndRefresh(toBN(2500, 18),
        {
          usdc: toBN(1000*1e6, 6),
          usdt: toBN(300*1e6, 6),
          dai: toBN(200*1e6, 6),
          weth: toBN(600*1e6, 18 + 30).div(WETH_PRICE),
          wbtc: toBN(300*1e6, 12 + 30).div(WBTC_PRICE),
        }
        ,
        {
          usdc: toBN(300, 6),
          usdt: toBN(0, 6),
          dai: toBN(0, 6),
          weth: toBN(100, 18 + 30).div(WETH_PRICE),
          wbtc: toBN(300, 12 + 30).div(WBTC_PRICE),
        },
        {
          usdc: 1500 / 2400,
          weth: 600 / 2400,
          wbtc: 300 / 2400,
        }
        ,
        {
          usdc: { precision: 4, staked: 299.3937, invested: 241.8937, notInvested: 57.5 },
          weth: { precision: 4, staked: 99.7575, invested: 96.7575, notInvested: 3 },
          wbtc: { precision: 4, staked: 299.8787, invested: 48.3787, notInvested: 251.5 },
        }
        ,
        {
          usdc: { precision: 4, staked: 299.3937, invested: 241.8937, notInvested: 57.5 },
          weth: { precision: 6, staked: 0.062348, invested: 0.060473, notInvested: 0.001875 },
          wbtc: { precision: 7, staked: 0.0124949, invested: 0.0020158, notInvested: 0.0104792 },
        }
      );

    });

  });

});
