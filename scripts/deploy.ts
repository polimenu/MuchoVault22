import { ethers } from "hardhat";

async function main() {

  const mUSDCc = await ethers.getContractFactory("mUSDC");
  const mUSDC = await mUSDCc.deploy();

  await mUSDC.deployed();

  console.log("Deployed at ", mUSDC.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
