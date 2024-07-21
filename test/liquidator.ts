import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import hre from "hardhat";

describe("Liquidator", function () {
  async function initState() {
    // owner: user admin of contracr
    // user1: user who wants to pay anything with crypto
    // user2: user who is a liquidator
    // user3: user who is a frog
    // user4: user who wants to pay with user1
    // user5: user who wants to pay with user1
    const [owner, user1, user2, user3, user4, user5] =
      await hre.ethers.getSigners();
    const Usdc = await hre.ethers.getContractFactory("USDC");
    const Liquidator = await hre.ethers.getContractFactory("Liquidator");
    const usdc = await Usdc.deploy(owner);
    const liquidators = [user2.address];
    const frogs = [user3.address];
    const usdcAddress = await usdc.getAddress();
    const liquidator = await Liquidator.deploy(usdcAddress, frogs, liquidators);
    // assign 1000 tokens to user1 and user4
    await usdc.mint(user1.address, 1000);
    await usdc.mint(user4.address, 1000);
    await usdc.mint(user5.address, 1000);
    return { usdc, liquidator, owner, user1, user2, user3, user4, user5 };
  }

  describe("Deployment", function () {
    it("Should to deploy smart contract and setup frogs and liquidators by default", async function () {
      const { owner, user1, user3, liquidator } = await loadFixture(initState);
      const frogs = [user3.address];
      // Owner is deployer address
      await expect(await liquidator.owner()).to.be.eq(owner.address);
      // Transactions start in zero
      await expect(await liquidator.totalTxs()).to.be.eq(0);
      // Paused default value is false
      await expect(await liquidator.paused()).to.be.eq(false);
      // profit estart with 0
      await expect(await liquidator.profit()).to.be.eq(0);
      // frogs
      for (let i = 0; i < frogs.length; i++) {
        await expect(await liquidator.frogs(frogs[i])).to.be.eq(true);
      }
      await expect(await liquidator.frogs(user1.address)).to.be.eq(false);
      await expect(await liquidator.balance(owner)).to.be.eq(0);
    });
  });

  describe("Transaction", function () {
    it("Should to create a transaction success", async function () {
      const { usdc, user1, user2, liquidator } = await loadFixture(initState);
      // permissions to liquidator to move 500 tokens usdc by user1
      const amount = 500;
      const liquidatorAddress = await liquidator.getAddress();
      const user1Address = user1.address;
      const user2Address = user2.address;
      await usdc.connect(user1).approve(liquidatorAddress, amount);
      // allowance at the beginning
      await expect(await usdc.allowance(user1Address, liquidator)).to.be.eq(
        amount
      );
      // Balance of users at the beginning
      await expect(await usdc.balanceOf(user1Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user2Address)).to.be.eq(0);
      // Call desposit function
      await liquidator
        .connect(user1)
        .deposit(amount, user2Address, [user1Address]);
      // Confirm transaction
      await liquidator.connect(user1).confirm();
      // Balance of users at the end
      await expect(await usdc.balanceOf(user1Address)).to.be.eq(500);
      await expect(await usdc.balanceOf(user2Address)).to.be.eq(500);
    });

    it("Should to create a transaction with a conflict but success", async function () {
      const { usdc, user1, user2, user3, liquidator } = await loadFixture(
        initState
      );
      // permissions to liquidator to move 500 tokens usdc by user1
      const amount = 500;
      const liquidatorAddress = await liquidator.getAddress();
      const user1Address = user1.address;
      const user2Address = user2.address;
      await usdc.connect(user1).approve(liquidatorAddress, amount);
      // allowance at the beginning
      await expect(await usdc.allowance(user1Address, liquidator)).to.be.eq(
        amount
      );
      // Balance of users at the beginning
      await expect(await usdc.balanceOf(user1Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user2Address)).to.be.eq(0);
      // Call desposit function
      await liquidator
        .connect(user1)
        .deposit(amount, user2Address, [user1Address]);
      // Confirm transaction by fake frog
      await expect(
        liquidator.connect(user2).confirmFrog(user1.address)
      ).to.be.revertedWith("Only the frogs can call this function");
      // Confirm transaction by frog
      await liquidator.connect(user3).confirmFrog(user1.address);
      // Balance of users at the end
      await expect(await usdc.balanceOf(user1Address)).to.be.eq(500);
      await expect(await usdc.balanceOf(user2Address)).to.be.eq(500);
    });

    it("Should to create a transaction with a conflict and revert it", async function () {
      const { usdc, user1, user2, user3, liquidator } = await loadFixture(
        initState
      );
      // permissions to liquidator to move 500 tokens usdc by user1
      const amount = 500;
      const liquidatorAddress = await liquidator.getAddress();
      const user1Address = user1.address;
      const user2Address = user2.address;
      await usdc.connect(user1).approve(liquidatorAddress, amount);
      // allowance at the beginning
      await expect(await usdc.allowance(user1Address, liquidator)).to.be.eq(
        amount
      );
      // Balance of users at the beginning
      await expect(await usdc.balanceOf(user1Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user2Address)).to.be.eq(0);
      // Call desposit function
      await liquidator
        .connect(user1)
        .deposit(amount, user2Address, [user1Address]);
      // revert transaction by fake frog
      await expect(
        liquidator.connect(user1).cancel(user1.address)
      ).to.be.revertedWith("Only the frogs can call this function");
      // revert transaction by frog
      await liquidator.connect(user3).cancel(user1.address);
      // Balance of users at the end
      await expect(await usdc.balanceOf(user1Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user2Address)).to.be.eq(0);
    });

    it("Should to create a transaction success with three users", async function () {
      const { usdc, user1, user2, user4, user5, liquidator } =
        await loadFixture(initState);
      // permissions to liquidator to move 500 tokens usdc by user1
      const amount = 500;
      const liquidatorAddress = await liquidator.getAddress();
      const user1Address = user1.address;
      const user2Address = user2.address;
      const user4Address = user4.address;
      const user5Address = user5.address;
      await usdc.connect(user1).approve(liquidatorAddress, amount);
      await usdc.connect(user4).approve(liquidatorAddress, amount);
      await usdc.connect(user5).approve(liquidatorAddress, amount);
      // allowance at the beginning
      await expect(await usdc.allowance(user1Address, liquidator)).to.be.eq(
        amount
      );
      await expect(await usdc.allowance(user4Address, liquidator)).to.be.eq(
        amount
      );
      await expect(await usdc.allowance(user5Address, liquidator)).to.be.eq(
        amount
      );
      // Balance of users at the beginning
      await expect(await usdc.balanceOf(user1Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user4Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user5Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user2Address)).to.be.eq(0);
      // Call desposit function
      await liquidator
        .connect(user1)
        .deposit(amount, user2Address, [
          user1Address,
          user4Address,
          user5Address,
        ]);
      // Confirm transaction
      await liquidator.connect(user1).confirm();
      // Balance of users at the end
      await expect(await usdc.balanceOf(user1Address)).to.be.eq(500);
      await expect(await usdc.balanceOf(user4Address)).to.be.eq(500);
      await expect(await usdc.balanceOf(user5Address)).to.be.eq(500);
      await expect(await usdc.balanceOf(user2Address)).to.be.eq(1500);
    });

    it("Should to create a transaction unsuccess with three users because one user didnt give permissions", async function () {
      const { usdc, user1, user2, user4, user5, liquidator } =
        await loadFixture(initState);
      // permissions to liquidator to move 500 tokens usdc by user1
      const amount = 500;
      const liquidatorAddress = await liquidator.getAddress();
      const user1Address = user1.address;
      const user2Address = user2.address;
      const user4Address = user4.address;
      const user5Address = user5.address;
      await usdc.connect(user1).approve(liquidatorAddress, amount);
      await usdc.connect(user4).approve(liquidatorAddress, amount);
      // allowance at the beginning
      await expect(await usdc.allowance(user1Address, liquidator)).to.be.eq(
        amount
      );
      await expect(await usdc.allowance(user4Address, liquidator)).to.be.eq(
        amount
      );
      await expect(await usdc.allowance(user5Address, liquidator)).to.be.eq(0);
      // Balance of users at the beginning
      await expect(await usdc.balanceOf(user1Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user4Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user5Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user2Address)).to.be.eq(0);
      // revert transaction by permissions denied for user5
      await expect(
        liquidator
          .connect(user1)
          .deposit(amount, user2Address, [
            user1Address,
            user4Address,
            user5Address,
          ])
      ).to.be.revertedWithCustomError(usdc, "ERC20InsufficientAllowance");
      // Balance of users at the end
      await expect(await usdc.balanceOf(user1Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user4Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user5Address)).to.be.eq(1000);
      await expect(await usdc.balanceOf(user2Address)).to.be.eq(0);
    });
  });
});
