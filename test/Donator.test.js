const { ethers, network } = require("hardhat");
const { expect } = require("chai");

let user, donationToken, donation, fund, cancelUser, receiver;

// Run tests with tracer
// npx hardhat test --trace      # shows logs + calls
// npx hardhat test --fulltrace  # shows logs + calls + sloads + sstores
// npx hardhat test --trace --opcodes ADD,SUB # shows any opcode specified

beforeEach(async function () {
  // environment preparation, deploy token & staking contracts
  const accounts = await ethers.getSigners();
  user = await accounts[3]; // Donor account
  fund = await accounts[4]; // Fund account
  cancelUser = await accounts[5]; // Cancel account
  receiver = await accounts[6]; // Receiver account

  const Token = await ethers.getContractFactory("Token");
  donationToken = await Token.deploy();

  const Usdc = await ethers.getContractFactory("Token");
  usdcToken = await Usdc.deploy();
  usdcToken.transfer(user.address, 3 * 5000000000);
  usdcToken.transfer(fund.address, 5000000000);

  const Usdt = await ethers.getContractFactory("Token");
  usdtToken = await Usdt.deploy();
  usdtToken.transfer(user.address, 5000000000);
  usdtToken.transfer(fund.address, 5000000000);

  const Donation = await ethers.getContractFactory("Funding");
  donation = await Donation.deploy(donationToken.address, usdtToken.address);
  stakeAmount = ethers.utils.parseUnits("1000000", 1);
  donationToken.transfer(user.address, stakeAmount);
  donationToken.transfer(cancelUser.address, 50000);
  donationToken.transfer(receiver.address, 50000);
  donationToken.transfer(fund.address, 50000);

  const Multi = await ethers.getContractFactory("EyeseekMulti");
  multiToken = await Multi.deploy();
  multiToken.safeTransferFrom(multiToken.address, user.address, 0, 1, "");

  await donation.createZeroData();
  const fundAmount = 500000000;
  await donation.connect(fund).createFund(fundAmount);

  return { Token, donationToken, donation, user, fund, cancelUser, receiver };
});

describe("Chain donation testing", async function () {
  it("Check funds + microfunds multiplication", async function () {
    const [user, fund] = await ethers.getSigners();

    const mainfund = 50000;
    const microfund = 500;
    const microfund2 = 500;
    const microfund3 = 500;
    const microfund4 = 500;
    const microfund5 = 50;

    const secondFund = 1500;

    const initial1 = 20;
    const initial2 = 20;
    const initial3 = 20;

    const donateAmount = 1;

    const allowance =
      microfund +
      microfund2 +
      microfund3 +
      microfund4 +
      microfund5 +
      initial1 +
      initial2 +
      initial3;

    await donation.connect(fund).createFund(mainfund);
    await donation.connect(fund).createFund(secondFund);
    await donationToken.approve(donation.address, allowance, {
      from: user.address,
    });
    // 3 Microfunds and 2 donations to involve
    await donation.contribute(0, donateAmount, 1, 1, 0, { from: user.address });
    await donation.contribute(microfund, 0, 1, 1, 0, { from: user.address });
    await donation.contribute(microfund, 0, 1, 1, 0, { from: user.address });
    await donation.contribute(microfund, 0, 1, 1, 0, { from: user.address });
    await donation.contribute(0, donateAmount, 1, 1, 0, { from: user.address });

    // const backers = await donation.getBackerAddresses(1)
    // expect(backers.length).to.equal(2)

    // Check multiplier, 4x multiplier from microfunds + donation
    const prediction = await donation.calcOutcome(1, 100);
    expect(prediction).to.equal(400);

    // Expected 3 microfunds
    const microfunds = await donation.getConnectedMicroFunds(1);
    expect(microfunds).to.equal(3);

    // Test distribution after completion
    // Closing microfunds, closing funds, token contract should be free of tokens
    // Distribute nefunguje
    await donation.distribute(1);
    const fundBalance = await donationToken.balanceOf(donation.address);
    expect(fundBalance).to.equal(0);
  });
  it("Cancel fund - Distributes resources back", async function () {
    const [user, fund] = await ethers.getSigners();
    const fundAmount = 500000000;
    const balanceBefore = await donationToken.balanceOf(user.address);
    await donationToken.approve(donation.address, 1 * fundAmount, {
      from: user.address,
    });
    await usdtToken.approve(donation.address, 2 * fundAmount, {
      from: user.address,
    });
    await donation.contribute(0, fundAmount, 1, 1, 0, { from: user.address });
    await donation.contribute(fundAmount, fundAmount, 1, 2, 0, {
      from: user.address,
    });

    await usdcToken.approve(donation.address, 500, { from: user.address });
    await donation.createReward(1, 1, 100, usdcToken.address, 1, {
      from: user.address,
    });
    await donation.createReward(1, 50, 1, usdcToken.address, 0, {
      from: user.address,
    });
    // Debug reward

    const multiBalance = await multiToken.balanceOf(user.address, 0);
    console.log("Multi balance before: " + multiBalance);
    await multiToken.setApprovalForAll(donation.address, true, {
      from: user.address,
    });
    //    await donation.createReward(1,1, multiToken.address, 0, {from: user.address})

    await donation.cancelFund(1, { from: user.address });
  });
});
