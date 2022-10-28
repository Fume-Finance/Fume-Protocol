//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./AssetManagement.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/** 
* @title Fund
* @author Fume Protocol
* 
* Implementation of an On-chain Fund. 
* This contracts issues funds units as ERC20 tokens. 
* It's used to process subscriptions and redemptions requests.
*/
contract Fund is ERC20, Ownable {
    uint256 constant BPSINPERCENTAGE = 100 * 100; // divide by this amount to convert a basis points fee to percentage
    uint256 constant DAYSTOSECONDS = 24 * 60 * 60; // multiply by this amount to convert from days to seconds

    // Management
    AssetManagement public assetManagement; // to segregate requests from the rest of the assets
    uint256 public nav; // in 1/1000th ether


    // Key Terms
    uint256 public managementFee; // basis points
    uint256 public performanceFee; // basis points
    uint256 public entryFee; // basis points
    uint256 public exitFee; // basis points
    bool public entryFeeToFund; // fee to Fund instead of Manager
    bool public exitFeeToFund; // fee to Fund instead of Manager
    uint256 public lockupPeriod; // in seconds

    // Subscriptions
    struct Subscription {
        address subscriber;
        uint256 amount;
    }
    mapping(address => bool) public whiteList; // mapping of whitelisted investors
    mapping(uint256 => Subscription) public subscriptions; // pending subscriptions requests
    uint256 public subscriptionIndex; // used to iterate over the mapping
    uint256 public pendingSubscriptionsAmount; // sum of pending subscriptions
    
    // Redemptions
    struct Redemption {
        address redeemer;
        uint256 units;
    }
    mapping(uint256 => Redemption) redemptions; // pending redemption requests
    uint256 redemptionIndex; // used to iterate over the mapping
    uint256 pendingRedemptionsUnits; // sum of pending redemptions


    constructor() ERC20("Cryptoro Fund Units", "CFU") {
        assetManagement = new AssetManagement(this, msg.sender);
    }


    // Check to ensure the investor is whitelisted.
    modifier whiteListed() {
        require(whiteList[msg.sender], "You're not whitelisted.");
        _;
    }


    // Set the key terms of the Fund for the setup.
    function setKeyTerms(uint256 _managementFee, uint256 _performanceFee, uint256 _entryFee, uint256 _exitFee, bool _entryFeeToFund, bool _exitFeeToFund, uint256 _lockupDays, uint256 _initialUnitPrice) public onlyOwner {
        require(_managementFee <= 10000, "Invalid management fee.");
        require(_performanceFee <= 10000, "Invalid performance fee.");
        require(_entryFee <= 10000, "Invalid entry fee.");
        require(_exitFee <= 10000, "Invalid exit fee.");
        require(_initialUnitPrice > 0, "Invalid initial unit price."); //check condition

        managementFee = _managementFee;
        performanceFee = _performanceFee;
        entryFee = _entryFee;
        exitFee = _exitFee;
        entryFeeToFund = _entryFeeToFund;
        exitFeeToFund = _exitFeeToFund;
        lockupPeriod = _lockupDays * DAYSTOSECONDS;
        nav = _initialUnitPrice * 1 ether / 1000;
    }


    // Override the usual 18 decimals. Smaller precision needed to better round NAV calculations.
    function decimals() public view virtual override returns (uint8) {
        return 5;
    }

    // Set new NAV
    function setNAV(uint256 _nav) public {
        require(msg.sender == address(assetManagement), "This function can only be called through the NAV Calculation");
        nav = _nav;
    }


    // Whitelist an investor after the KYC.
    function kycApproval(address _newInvestor) public onlyOwner {
        whiteList[_newInvestor] = true;
    }


    // Rekove access to an investor
    function kycRevoke(address _Investor) public onlyOwner {
        whiteList[_Investor] = false;
    }


    // Subscribe to the Fund
    // #value: the amount in eth to be invested
    function subscribe() public whiteListed payable {
        require(msg.value > 0, "Empty subscription");
        subscriptions[subscriptionIndex].subscriber = msg.sender;
        subscriptions[subscriptionIndex].amount = msg.value;
        pendingSubscriptionsAmount += msg.value;
        subscriptionIndex++;
    }


    // Redeem units from the Fund
    function redeem(uint256 _units) public whiteListed {
        require(_units <= balanceOf(msg.sender), "Not enough units to redeem");
        transfer(address(this), _units);

        redemptions[redemptionIndex].redeemer = msg.sender;
        redemptions[redemptionIndex].units = _units;
        pendingRedemptionsUnits += _units;
        redemptionIndex++;
    }
    

    // Execute the pending subscriptions and redemptions
    function executeRequests() public payable {
        require(msg.sender == address(assetManagement), "This function can only be called through the NAV Calculation");

        /* ----- Subscription Requests ----- */
        uint256 totalSubscriptionFees; // sum of subscription fees
        uint256 totalSubscribedAmount; // sum of subscribed amounts (=deposit - entryfees)

        for (uint i=0; i<subscriptionIndex; i++) {
            uint256 subscriptionFee = (subscriptions[i].amount * entryFee) / BPSINPERCENTAGE;
            uint256 subscribedAmount = subscriptions[i].amount - subscriptionFee;
            totalSubscriptionFees += subscriptionFee;
            totalSubscribedAmount += subscribedAmount;

            uint256 toBeMinted = (subscribedAmount * (10 ** decimals()))/nav; // adjust for decimals
            _mint(subscriptions[i].subscriber, toBeMinted); // new fund units are issued to the investor
        }

        bool success;
        if(entryFeeToFund){ // entry fees are for the fund
            (success, /*bytes memory data*/) = address(assetManagement).call{value: totalSubscriptionFees}("");
            require(success, "Unsuccessuful fee payment");
        } else { // entry fees are for the manager
            (success, /*bytes memory data*/) = owner().call{value: totalSubscriptionFees}(""); 
            require(success, "Unsuccessuful fee payment");
        }

        subscriptionIndex = 0; // reset pending subscription requests
        pendingSubscriptionsAmount = 0; // note: no need to clean up the mapping

        (success, /*bytes memory data*/) = address(assetManagement).call{value: totalSubscribedAmount}(""); // The pending liquidity is now part of the fund's assets
        require(success, "Unsuccessuful subscription payment");


        /* ----- Redemption Requests ----- */
        uint256 totalRedemptionFees; // sum of redemption fees
        uint256 totalRedeemedUnits; // sum of redeemped units (=redeemed units - entryfees)

        for (uint i=0; i<redemptionIndex; i++) {
            uint256 redemptionFee = (redemptions[i].units * exitFee) / BPSINPERCENTAGE;
            uint256 redeemedUnits = redemptions[i].units - redemptionFee;
            totalRedemptionFees += redemptionFee;
            totalRedeemedUnits += redeemedUnits;
        
            uint256 toBeWithdrawn = redeemedUnits * nav / 10 ** decimals(); // adjust for decimals
            assetManagement.withdrawLiquidity(redemptions[i].redeemer, toBeWithdrawn); // The liquidity is now withdrawn from the fund's assets
        }

        if(exitFeeToFund){ // exit fees are for the fund
            _burn(address(this), totalRedemptionFees);
        } else { // exit fees are for the manager
            transfer(owner(), totalRedemptionFees);
        }

        redemptionIndex = 0; // reset pending redemption requests
        pendingRedemptionsUnits = 0;

        _burn(address(this), totalRedeemedUnits);
    }
}
