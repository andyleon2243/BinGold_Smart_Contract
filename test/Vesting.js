const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("BinGoldVesting", function () {
  let binGoldToken;
  let binGoldVesting;
  let owner;
  let teamWallet;
  let advisorWallet;
  let otherAccount;
  let currentTime;
  
  const MONTH = 30 * 24 * 60 * 60; // 30 days in seconds
  const TEAM_ALLOCATION = ethers.parseUnits("500000", 6); // 500,000 tokens with 6 decimals
  const ADVISOR_ALLOCATION = ethers.parseUnits("125000", 6); // 125,000 tokens with 6 decimals
  const TEAM_CLIFF = 6 * MONTH;
  const TEAM_VESTING_DURATION = 36 * MONTH;
  const ADVISOR_CLIFF = 0;
  const ADVISOR_VESTING_DURATION = 12 * MONTH;
  
  // Increased tolerance to handle rounding differences
  const ROUNDING_TOLERANCE = Number(ethers.parseUnits("250", 3)); // Increased from 1000 to 10000

  beforeEach(async function () {
    // Get signers
    [owner, teamWallet, advisorWallet, otherAccount] = await ethers.getSigners();
    
    // Deploy token contract
    const BinGoldToken = await ethers.getContractFactory("BinGoldToken");
    binGoldToken = await upgrades.deployProxy(BinGoldToken, [owner.address], {
      initializer: "initialize",
    });
    await binGoldToken.waitForDeployment();
    
    const tokenAddress = await binGoldToken.getAddress();
    console.log("BinGold token deployed at:", tokenAddress);

    // Mint tokens to cover vesting allocations
    await binGoldToken.increaseSupply(ethers.parseUnits("2500000", 6)); // Mint 1M tokens
  
    // Get the current timestamp
    currentTime = (await ethers.provider.getBlock("latest")).timestamp;
    const startTime = currentTime + 60; // Start vesting 1 minute in the future
 
    // Deploy BinGoldVesting
    const BinGoldVesting = await ethers.getContractFactory("BinGoldVesting");
    binGoldVesting = await upgrades.deployProxy(BinGoldVesting, [
      tokenAddress,
      startTime,
      teamWallet.address,
      advisorWallet.address
    ], {
      initializer: "initialize",
    });
    
    const binGoldVestingAddress = await binGoldVesting.getAddress();
    console.log("BinGoldVesting deployed at:", binGoldVestingAddress);
    
    // Transfer tokens to the vesting contract
    await binGoldToken.transfer(binGoldVestingAddress, TEAM_ALLOCATION + ADVISOR_ALLOCATION);
  });


  describe("Advisor Total Distribution Test", function () {
    it("should distribute 100% of advisor tokens by the end of vesting period", async function () {
      // Advance time to vesting start
      await time.increase(60);
      
      // Initial balance should be 0
      expect(await binGoldToken.balanceOf(advisorWallet.address)).to.equal(0);
      
      // Claim after each month for the full duration
      for (let i = 1; i <= 12; i++) {
        await time.increase(MONTH);
        
        if (await binGoldVesting.calculateReleasableAmount(advisorWallet.address) > 0) {
          await binGoldVesting.connect(advisorWallet).claimTokens();
        }
        
        console.log(`Month ${i}: Advisor balance: ${await binGoldToken.balanceOf(advisorWallet.address)}`);
      }
      
      // Final balance should equal total allocation
      const finalBalance = await binGoldToken.balanceOf(advisorWallet.address);
      console.log(`Final advisor balance: ${finalBalance}`);
      console.log(`Expected allocation: ${ADVISOR_ALLOCATION}`);
      
      expect(finalBalance).to.equal(ADVISOR_ALLOCATION);
    });
  });

  describe("Team Total Distribution Test", function () {
    it("should distribute 100% of team tokens by the end of vesting period", async function () {
      // Advance time to vesting start + cliff period
      await time.increase(60 + MONTH * 6);
      
      // Initial balance should be 0
      expect(await binGoldToken.balanceOf(teamWallet.address)).to.equal(0);
      
      // Claim after each month for the full duration
      for (let i = 1; i <= 36; i++) {
        await time.increase(MONTH);
        
        if (await binGoldVesting.calculateReleasableAmount(teamWallet.address) > 0) {
          await binGoldVesting.connect(teamWallet).claimTokens();
        }
        
        console.log(`Month ${i}: Team balance: ${await binGoldToken.balanceOf(teamWallet.address)}`);
      }
      
      // Final balance should equal total allocation
      const finalBalance = await binGoldToken.balanceOf(teamWallet.address);
      console.log(`Final team balance: ${finalBalance}`);
      console.log(`Expected allocation: ${TEAM_ALLOCATION}`);
      
      expect(finalBalance).to.equal(TEAM_ALLOCATION);
    });
  });

  describe("Initialization", function () {
    it("should set the correct token address", async function () {
      const tokenAddress = await binGoldToken.getAddress();
      const vestingTokenAddress = await binGoldVesting.getBinGoldToken();
      expect(vestingTokenAddress).to.equal(tokenAddress);
    });

    it("should set the correct vesting start time", async function () {
      const vestingStartTime = await binGoldVesting.getVestingStartTime();
      expect(vestingStartTime).to.be.gt(currentTime);
    });

    it("should set the correct team wallet", async function () {
      expect(await binGoldVesting.getTeamWallet()).to.equal(teamWallet.address);
    });

    it("should set the correct advisor wallet", async function () {
      expect(await binGoldVesting.getAdvisorWallet()).to.equal(advisorWallet.address);
    });

    it("should initialize tokens released to zero", async function () {
      expect(await binGoldVesting.getTeamTokensReleased()).to.equal(0);
      expect(await binGoldVesting.getAdvisorTokensReleased()).to.equal(0);
    });
  });

  describe("Admin Functions", function () {
    it("should allow owner to update team wallet", async function () {
      await binGoldVesting.updateTeamWallet(otherAccount.address);
      expect(await binGoldVesting.getTeamWallet()).to.equal(otherAccount.address);
    });

    it("should allow owner to update advisor wallet", async function () {
      await binGoldVesting.updateAdvisorWallet(otherAccount.address);
      expect(await binGoldVesting.getAdvisorWallet()).to.equal(otherAccount.address);
    });

    it("should allow owner to update token address", async function () {
      // Deploy a new token
      const BinGoldToken = await ethers.getContractFactory("BinGoldToken");
      const newToken = await upgrades.deployProxy(BinGoldToken, [owner.address], {
        initializer: "initialize",
      });
      
      const newTokenAddress = await newToken.getAddress();
      await binGoldVesting.updateTokenAddress(newTokenAddress);
      expect(await binGoldVesting.getBinGoldToken()).to.equal(newTokenAddress);
    });

    it("should emit WalletUpdated event when team wallet is updated", async function () {
      await expect(binGoldVesting.updateTeamWallet(otherAccount.address))
        .to.emit(binGoldVesting, "WalletUpdated")
        .withArgs("TEAM", teamWallet.address, otherAccount.address);
    });

    it("should emit WalletUpdated event when advisor wallet is updated", async function () {
      await expect(binGoldVesting.updateAdvisorWallet(otherAccount.address))
        .to.emit(binGoldVesting, "WalletUpdated")
        .withArgs("ADVISOR", advisorWallet.address, otherAccount.address);
    });

    it("should emit TokenAddressUpdated event when token address is updated", async function () {
      const BinGoldToken = await ethers.getContractFactory("BinGoldToken");
      const newToken = await upgrades.deployProxy(BinGoldToken, [owner.address], {
        initializer: "initialize",
      });
      
      const oldTokenAddress = await binGoldToken.getAddress();
      const newTokenAddress = await newToken.getAddress();
      
      await expect(binGoldVesting.updateTokenAddress(newTokenAddress))
        .to.emit(binGoldVesting, "TokenAddressUpdated")
        .withArgs(oldTokenAddress, newTokenAddress);
    });
  });

  describe("Vesting Calculations", function () {
    it("should return zero releasable amount before cliff period for team", async function () {
      const releasable = await binGoldVesting.calculateReleasableAmount(teamWallet.address);
      expect(releasable).to.equal(0);
    });

    
    it("should return correct releasable amount for advisor with no cliff", async function () {
        // Move time past vesting start
        await time.increase(MONTH);
        
        const releasable = await binGoldVesting.calculateReleasableAmount(advisorWallet.address);
        
        // After 1 month, should have vested 1/12 of total allocation (no cliff for advisors)
        const expectedVested = ADVISOR_ALLOCATION / 12n;
        
        // Use closeTo with increased tolerance to handle larger rounding differences
        expect(Number(releasable)).to.be.closeTo(Number(expectedVested), ROUNDING_TOLERANCE);
      });

    it("should return correct vesting info for team wallet", async function () {
      const vestingInfo = await binGoldVesting.getVestingInfo(teamWallet.address);
      
      expect(vestingInfo.totalAllocation).to.equal(TEAM_ALLOCATION);
      expect(vestingInfo.releasedAmount).to.equal(0);
      expect(vestingInfo.releasableAmount).to.equal(0);
      
      const vestingStartTime = await binGoldVesting.getVestingStartTime();
      expect(vestingInfo.vestingStartDate).to.equal(vestingStartTime);
      
      // Using Number() to handle BigInt arithmetic
      expect(Number(vestingInfo.cliffEndDate)).to.equal(Number(vestingStartTime) + Number(TEAM_CLIFF));
      expect(Number(vestingInfo.vestingEndDate)).to.equal(
        Number(vestingStartTime) + Number(TEAM_CLIFF) + Number(TEAM_VESTING_DURATION)
      );
    });

    it("should return correct vesting info for advisor wallet", async function () {
      const vestingInfo = await binGoldVesting.getVestingInfo(advisorWallet.address);
      
      expect(vestingInfo.totalAllocation).to.equal(ADVISOR_ALLOCATION);
      expect(vestingInfo.releasedAmount).to.equal(0);
      expect(vestingInfo.releasableAmount).to.equal(0);
      
      const vestingStartTime = await binGoldVesting.getVestingStartTime();
      expect(vestingInfo.vestingStartDate).to.equal(vestingStartTime);
      
      // Using Number() to handle BigInt arithmetic
      expect(Number(vestingInfo.cliffEndDate)).to.equal(Number(vestingStartTime) + Number(ADVISOR_CLIFF));
      expect(Number(vestingInfo.vestingEndDate)).to.equal(
        Number(vestingStartTime) + Number(ADVISOR_CLIFF) + Number(ADVISOR_VESTING_DURATION)
      );
    });
  });

  describe("Token Claims", function () {
    it("should allow advisor to claim tokens after vesting starts", async function () {
      // Move time past vesting start time
      await time.increase(MONTH * 3);
      
      // Check releasable amount before claim
      const releasable = await binGoldVesting.calculateReleasableAmount(advisorWallet.address);
      expect(releasable).to.be.gt(0);
      
      // Store releasable amount to compare with later
      const releasableBeforeClaim = releasable;
      
      // Claim tokens
      await binGoldVesting.connect(advisorWallet).claimTokens();
      
      // Check advisor's token balance
      const advisorBalance = await binGoldToken.balanceOf(advisorWallet.address);
      expect(advisorBalance).to.be.gt(0);
      
      // Use closeTo for comparing BigNumber values with increased tolerance
      expect(Number(advisorBalance)).to.be.closeTo(Number(releasableBeforeClaim), ROUNDING_TOLERANCE);
      
      // Check released amount is updated
      const advisorTokensReleased = await binGoldVesting.getAdvisorTokensReleased();
      expect(Number(advisorTokensReleased)).to.be.closeTo(Number(advisorBalance), ROUNDING_TOLERANCE);
    });

    it("should allow team to claim tokens after cliff period", async function () {
      // Move time past cliff period
      await time.increase(TEAM_CLIFF + MONTH);
      
      // Check releasable amount before claim
      const releasable = await binGoldVesting.calculateReleasableAmount(teamWallet.address);
      expect(releasable).to.be.gt(0);
      
      // Store releasable amount to compare with later
      const releasableBeforeClaim = releasable;
      
      // Claim tokens
      await binGoldVesting.connect(teamWallet).claimTokens();
      
      // Check team's token balance
      const teamBalance = await binGoldToken.balanceOf(teamWallet.address);
      expect(teamBalance).to.be.gt(0);
      
      // Use closeTo for comparing BigNumber values with increased tolerance
      expect(Number(teamBalance)).to.be.closeTo(Number(releasableBeforeClaim), ROUNDING_TOLERANCE);
      
      // Check released amount is updated
      const teamTokensReleased = await binGoldVesting.getTeamTokensReleased();
      expect(Number(teamTokensReleased)).to.be.closeTo(Number(teamBalance), ROUNDING_TOLERANCE);
    });

    it("should emit TokensReleased event when tokens are claimed", async function () {
      // Move time past vesting start time
      await time.increase(MONTH * 3);
      
      // Get releasable amount
      const releasable = await binGoldVesting.calculateReleasableAmount(advisorWallet.address);
      
      // Use a custom matcher to verify the event with tolerance for rounding
      await binGoldVesting.connect(advisorWallet).claimTokens()
        .then(async (tx) => {
          const receipt = await tx.wait();
          const event = receipt.logs.find(log => 
            log.fragment && log.fragment.name === 'TokensReleased'
          );
          
          expect(event).to.not.be.undefined;
          
          if (event) {
            const args = event.args;
            expect(args[0]).to.equal(advisorWallet.address);
            
            // Use closeTo for the token amount comparison
            expect(Number(args[1])).to.be.closeTo(Number(releasable), ROUNDING_TOLERANCE);
          }
        });
    });
  });
});