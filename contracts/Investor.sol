//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Fund.sol";

/** 
* @title Investor
* @author Fume Protocol
* 
* Exclusively used for testing.
* Simplifies the similution of the investors' interactions.
*/
contract Investor {

    Fund fund;

    constructor(Fund _fund) {
        fund = _fund;
    }

    function subscribeToFund() public payable {
        fund.subscribe{value: msg.value}();
    }

    function redeemFromFund(uint256 _units) public {
        fund.redeem(_units);
    }

    // Needed to receive liquidity from the Fund
    receive() external payable{}
    fallback() external payable {}
}
