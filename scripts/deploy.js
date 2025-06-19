const { ethers } = require("hardhat");

async function main() {
  // Get contract factories
  const Upgradeability = await ethers.getContractFactory("OwnedUpgradeabilityProxy");
  const GLDBST = await ethers.getContractFactory("BinGoldToken");
  const vesting = await ethers.getContractFactory("BinGoldVesting");


  console.log("Deploying GLDBST implementation contract...");
  const gld_contract = await GLDBST.deploy();
  await gld_contract.waitForDeployment();
  const gld_contract_address = await gld_contract.getAddress();
  console.log("GLDBST deployed at:", gld_contract_address);

  console.log("Deploying Proxy contract...");
  const proxy1 = await Upgradeability.deploy();
  await proxy1.waitForDeployment();
  const proxy_address = await proxy1.getAddress();
  console.log("Proxy deployed at:", proxy_address);

  // Encode initialization data
  const initializeData = GLDBST.interface.encodeFunctionData("initialize", [
    "0x79f28C559f672d178Acfb3d09f38E686D98FeD4A"// Your initialization address
  ]);

  // Upgrade proxy to use GLDBST logic
  console.log("Upgrading proxy to use GLDBST...");
  const tx = await proxy1.upgradeToAndCall(gld_contract_address, initializeData);
  await tx.wait();
  console.log("Proxy successfully upgraded to GLDBST implementation");




  //Deploy Vesting

  console.log("Deploying Proxy contract for vesting...");
  const proxy2 = await Upgradeability.deploy();
  await proxy2.waitForDeployment();
  const proxy_address_vesitng = await proxy2.getAddress();
  console.log("Vesting Proxy deployed at:", proxy_address_vesitng);

    const vesting_contract = await vesting.deploy();
  await vesting_contract.waitForDeployment();
  const vesting_address = await vesting_contract.getAddress();
  console.log("vesting deployed at:", vesting_address);

    const initializeData2 = vesting.interface.encodeFunctionData("initialize", [
    proxy_address,
    1750339911,
    "0xD032f9375C94A9dA68FbB71fdE5aC1eE3C281163",
    "0xAe9131f57721Acc75eB49696eFD95AD1455269F5"
  ]);

  const tx2 = await proxy2.upgradeToAndCall(vesting_address, initializeData2);
  await tx.wait();
  console.log("Proxy successfully upgraded to vesting implementation");

}

// Execute the deployment script
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
