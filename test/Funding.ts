import { assert, expect } from "chai";
import { ethers, network } from "hardhat";

import {
  DiamondLoupeFacet,
  FundFacet,
  MasterFacet,
  OwnershipFacet,
  RewardFacet,
  Token,
} from "../typechain-types";

import { deployDiamond } from "../scripts/deploy";
import { BigNumber } from "ethers";

describe("Funding", async function () {
  let diamondAddress: string;
  let diamondLoupeFacet: DiamondLoupeFacet;
  // let ownershipFacet: OwnershipFacet;
  let fundFacet: FundFacet;
  // let rewardFacet: RewardFacet;
  let masterFacet: MasterFacet;

  let donationToken: Token;

  before(async function () {
    // ## Setup Donation Token
    const Token = await ethers.getContractFactory("Token");
    donationToken = await Token.deploy();

    // ## Setup Diamond

    // Pass list of facets to add in addition to the base DiamondLoupeFacet, DiamondCutFacet and OwnershipFacet
    diamondAddress = await deployDiamond(
      ["FundFacet", "RewardFacet", "MasterFacet"],
      donationToken.address
    );

    diamondLoupeFacet = await ethers.getContractAt(
      "DiamondLoupeFacet",
      diamondAddress
    );
    // ownershipFacet = await ethers.getContractAt(
    //   "OwnershipFacet",
    //   diamondAddress
    // );
    fundFacet = await ethers.getContractAt("FundFacet", diamondAddress);
    // rewardFacet = await ethers.getContractAt("RewardFacet", diamondAddress);
    masterFacet = await ethers.getContractAt("MasterFacet", diamondAddress);
  });

  it("should have all facets -- call to facetAddresses function", async () => {
    const addresses = [];
    for (const address of await diamondLoupeFacet.facetAddresses()) {
      addresses.push(address);
    }
    assert.equal(addresses.length, 6);
  });

  it("FundFacet - createFund with funds starting at index 0", async () => {
    // First fund has index 0
    const tx = fundFacet.createFund(1000);
    await expect(tx)
      .to.emit(fundFacet, "FundCreated")
      .withArgs(BigNumber.from(0));

    // Second fund has index 1
    const tx2 = fundFacet.createFund(2000);
    await expect(tx2)
      .to.emit(fundFacet, "FundCreated")
      .withArgs(BigNumber.from(1));
  });
  it("MasterFacet facet - contribute to fund with index 1 with no errors", async () => {
    // Approve 50 tokens for contributing
    await donationToken.approve(diamondAddress, 50);
    // Contribute to 2nd fund (index 1)
    await masterFacet.contribute(0, 50, 1, 0, 0);
  });
});
