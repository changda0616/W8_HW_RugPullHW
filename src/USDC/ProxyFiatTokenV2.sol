// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.17;

import {IERC20} from "../TradingCenter.sol";

// Current USDC Proxy
interface ProxyFiatTokenV2 {
    function upgradeTo(address newImplementation) external;

    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable;

    function implementation() external view returns (address);

    function changeAdmin(address newAdmin) external;

    function admin() external view returns (address);
}
