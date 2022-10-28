//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Fund.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/** 
* @title AssetManagement
* @author Fume Protocol
* 
* The asset management is segregated from the fund. 
* This contracts holds assets and liabilities. 
* It computes NAV calculations.
*/
contract AssetManagement is Ownable {
    
    Fund fund;
    uint256 highWaterMark;

    // Assets
    struct Asset {
        //string name;
        //bool directHolding;
        //address tokenAddress;
        uint amount;
        uint256 price; // asset price in eth
    }
    mapping(string => Asset) public assets;
    mapping(string => bool) public assetExist; 
    string[] public assetList;

    // Liabilities
    struct Liability {
        //string name;
        //bool directHolding;
        //address tokenAddress;
        uint amount;
        uint256 price; // liability price in eth
    }
    mapping(string => Liability) public liabilities;
    mapping(string => bool) liabilityExist; 
    string[] public liabilityList;


    // Links its Fund and assigns its ownership to the manager
    constructor(Fund _fund, address _fundOwner) {
        fund = _fund;
        transferOwnership(_fundOwner);
    }


    // Add an external position to the Fund
    function addAsset(string memory _asset, uint256 _amount, uint256 _price) public onlyOwner {
        require(_amount > 0, "Nothing to add.");

        if(!assetExist[_asset]){
            assetList.push(_asset);
        }

        assets[_asset] = Asset(_amount, _price);
        assetExist[_asset] = true;
    }


    // Calculates the Gross Asset Value (Sum of all assets)
    function gavCalculation() private view returns(uint256){
        uint256 gav;
        for (uint i=0; i<assetList.length; i++) {
            gav += assets[assetList[i]].amount * assets[assetList[i]].price;
        }

        gav += address(this).balance;
        return gav;    
    }


    // Add a pending libility to the Fund
    function addLiability(string memory _liability, uint256 _amount, uint _price) public onlyOwner {
        require(_amount > 0, "Nothing to add.");

        if(!liabilityExist[_liability]){
            liabilityList.push(_liability);
        }

        liabilities[_liability] = Liability(_price, _amount);
        liabilityExist[_liability] = true; 
    }

    // Calculates the Liabilities (Sum of all liabilities)
    function liabilitiesCalculation() private view returns(uint256){
        uint256 totLiabilities;
        for (uint i=0; i<liabilityList.length; i++) {
            totLiabilities += liabilities[liabilityList[i]].amount * liabilities[liabilityList[i]].price;
        }
        return totLiabilities;      
    }

    // To initiate the fund before (i.e. before the first NAV calculation)
    function openFund() public onlyOwner {
        fund.executeRequests();
    }

    // Calculates the Net Asset Value
    // NAV = (Assets - Liabilities) / Total number of outstanding shares
    function navCalculation() public onlyOwner returns(uint256) {
        uint256 newNAV = (gavCalculation() - liabilitiesCalculation()) / (fund.totalSupply() / (10 ** fund.decimals())); // Adjust for decimals
        fund.setNAV(newNAV);
        fund.executeRequests();
        return newNAV;
    }


    // Repays an investor at the redemption procedure.
    function withdrawLiquidity(address _to, uint256 _amount) public payable {
        require(msg.sender == address(fund), "This function can only be called through the execution of requests");
        require(_amount <= address(this).balance, "Not enough liquidity to withdraw");

        (bool success, /*bytes memory data*/) = _to.call{value: _amount}("");
        require(success, "Unsuccessuful redemption payment");
    }


    // Repays investors keeping the due fees and close the fund.
    function closeFund() public onlyOwner {
        /* TODO - Force redemption */
        selfdestruct(payable(owner())); //SELFDESTRUCT might be removed in future ethereum protocol upgrade
    }


    // Needed to receive liquidity from the Fund
    receive() external payable{} 
    fallback() external payable{}
}
