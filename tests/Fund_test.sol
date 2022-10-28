// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "remix_tests.sol"; // this import is automatically injected by Remix.
import "remix_accounts.sol";
import "hardhat/console.sol";
import "../contracts/Fume/Fund.sol";
import "../contracts/Fume/AssetManagement.sol";
import "../contracts/Fume/Investor.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract FundTest {
    
    Fund public fundToTest;
    AssetManagement public amToTest;
    Investor investor;


    function beforeAll() public {
        fundToTest = new Fund();
        amToTest = fundToTest.assetManagement();
        fundToTest.setKeyTerms(200, 2000, 100, 100, false, true, 365, 1);
    }

    function checkKeyTerms() public {
        console.log("Checking the Key Terms");

        Assert.equal(fundToTest.managementFee(), 200, "Management fee should be 200.");
        Assert.equal(fundToTest.performanceFee(), 2000, "Performance fee should be 2000.");
        Assert.equal(fundToTest.entryFee(), 100, "Entry fee should be 100.");
        Assert.equal(fundToTest.exitFee(), 100, "Exit fee should be 100.");
        Assert.equal(fundToTest.entryFeeToFund(), false, "Entry not to the fund.");
        Assert.equal(fundToTest.exitFeeToFund(), true, "Exit to the fund.");
        Assert.equal(fundToTest.lockupPeriod(), 365 * 24 * 60 * 60, "Wrong Lockup period");
        Assert.equal(fundToTest.nav(), 1 ether / 1000, "Initial Nav should be 1/1000th of ether.");
    }

    function checkKyc() public {
        investor = new Investor(fundToTest);
        Assert.equal(fundToTest.whiteList(address(investor)), false, "Before KYC, it should be false");
        fundToTest.kycApproval(address(investor));
        Assert.equal(fundToTest.whiteList(address(investor)), true, "After KYC, it should be true");
    }

    /// First Deposit of 1 ether
    /// #value: 1000000000000000000
    function checkFirstDeposit() public payable {
        Assert.equal(msg.value, 1 ether, "Deposit value not 1 ether");
        Assert.equal(address(fundToTest).balance, 0, "Fund isn't empty at the beginning");

        //address investorAddress = address(investor);
        //payable(investorAddress).transfer(msg.value);
        investor.subscribeToFund{value: msg.value}();

        Assert.equal(address(fundToTest).balance, msg.value, "Fund doesn't contain the initial deposit");
        console.log(Strings.toString(address(fundToTest).balance));
        console.log(Strings.toString(fundToTest.pendingSubscriptionsAmount()));
        Assert.equal(fundToTest.pendingSubscriptionsAmount(), 1000000000000000000, "Fund doesn't contain the initial amount");
    }


    function checkOpenFund() public {
        Assert.equal(fundToTest.totalSupply(), 0, "Initial Supply not zero");
        Assert.equal(fundToTest.balanceOf(address(investor)), 0, "Initial balance not zero");

        amToTest.openFund();

        // 1000000000000000000*(1-0.01)/(1000000000000000000/1000)
        uint256 expectedUnits = 990 * (10 ** fundToTest.decimals());
        Assert.equal(fundToTest.totalSupply(), expectedUnits, "Incorrect First Nav Supply");
        Assert.equal(fundToTest.balanceOf(address(investor)), expectedUnits, "Incorrect First balance");
        Assert.equal(address(this).balance, 10000000000000000, "Incorrect Fee Paid to FM");
        Assert.equal(address(fundToTest).balance, 0, "Incorrect remaining in the Fund");
        Assert.equal(address(amToTest).balance, 990000000000000000, "Incorrect amount sent in the AM");
    }

    function checkInitialNavCalculation() public {
        uint256 sameInitialNav = amToTest.navCalculation();

        Assert.equal(sameInitialNav, 1 ether / 1000, "Incorrect Initial Nav");
        Assert.equal(address(this).balance, 10000000000000000, "Incorrect Fee Paid to FM");
        Assert.equal(address(amToTest).balance, 990000000000000000, "Incorrect amount sent in the AM");
        Assert.equal(fundToTest.balanceOf(address(investor)), 990 * (10 ** fundToTest.decimals()), "Incorrect First balance");
    }

    function checkAddingAssets() public {
        amToTest.addAsset("Villa Lugano", 1, 990000000000000000);

        uint256 newNav = amToTest.navCalculation();
        Assert.equal(newNav, 2 ether / 1000, "Incorrect new Nav");
    }

    function checkAddingLiabilities() public {
        amToTest.addLiability("CSSF Registration Tax", 1, 990000000000000000);

        uint256 newNav = amToTest.navCalculation();
        Assert.equal(newNav, 1 ether / 1000, "Incorrect new Nav");
    }

    function checkRedemption() public {
        Assert.equal(fundToTest.balanceOf(address(investor)), 990 * (10 ** fundToTest.decimals()), "Incorrect units before redemption");
        investor.redeemFromFund(990 * (10 ** fundToTest.decimals()));
        Assert.equal(fundToTest.balanceOf(address(investor)), 0, "Incorrect units after redemption");
        Assert.equal(fundToTest.balanceOf(address(fundToTest)), 990 * (10 ** fundToTest.decimals()), "Incorrect units after redemption pending");
        Assert.equal(fundToTest.totalSupply(), 990 * (10 ** fundToTest.decimals()), "Incorrect total Supply before NAV");

        uint256 newNav = amToTest.navCalculation();
        Assert.equal(newNav, 1 ether / 1000, "Incorrect new Nav");
        Assert.equal(fundToTest.balanceOf(address(fundToTest)), 0, "Incorrect units after redemption executed");
        Assert.equal(fundToTest.totalSupply(), 0, "Incorrect total Supply after NAV");
        Assert.equal(address(amToTest).balance, 9900000000000000, "Incorrect amount remaining in the AM");
        Assert.equal(address(investor).balance, 980100000000000000, "Incorrect Redemption Paid to the investor");
    }


    receive() external payable{}

    fallback() external payable {}
}
