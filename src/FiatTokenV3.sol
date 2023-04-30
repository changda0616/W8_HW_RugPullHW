// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.17;

import "./Proxy.sol";
import {IERC20} from "./TradingCenter.sol";
import {OwnableFiatTokenV2} from "./USDC/OwnableFiatTokenV2.sol";

interface IMintable {
    function mint(address _to, uint256 _amount) external returns (bool);

    function updateMasterMinter(address _newMasterMinter) external;

    function minterAllowance(address minter) external view returns (uint256);

    function isMinter(address account) external view returns (bool);
}

// Owner of WhitleList will be the new implementation contract, FiatTokenV3.
// If we set the owner to the USDC's contract owner (EOA), then we will not pass the onlyOwner modifier on setWhiteList.
// And here's the reason, to contract WhiteList,
// the msg.sender is FiatTokenV3 while we use pure **call** doing whiteListContract.setWhiteList(account) in the function addToWhiteList.
// And we can't use delegatecall in this case, since we want to keep the state whiteList existed only in the contract WhitleList itself,
// so we can avoid storage collision in the current USDC contract.
contract WhitleList is OwnableFiatTokenV2 {
    mapping(address => bool) public whiteList;

    constructor(address value) {
        setOwner(value);
    }

    function setWhiteList(address account) public onlyOwner returns (bool) {
        whiteList[account] = true;
        return true;
    }

    function removeWhiteList(address account) public onlyOwner returns (bool) {
        delete whiteList[account];
        return true;
    }
}

contract FiatTokenV3 is Proxy, OwnableFiatTokenV2 {
    bytes32 private constant WHITELIST_SLOT =
        0xf0f44d0dc71ced2657102758a6470189e14da69bd82c2d77dd2de1676a0e1520;
    bytes32 private constant INITIALIZED_SLOT =
        0xad7a544c9a563be9238eb7ce30bfaff12fddfec5882f12a893a2bbd6e9d4c959;
    address constant CURRENT_USDC_IMPLEMENTATION =
        0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF;

    event Log(bytes32 indexed data, address indexed addr);

    constructor() {
        assert(WHITELIST_SLOT == keccak256("fiatTokenV3.whiteList"));
        assert(INITIALIZED_SLOT == keccak256("fiatTokenV3.initialized"));
        setOwner(msg.sender);
    }

    function initialize() public {
        require(
            !_initialized(),
            "Contract instance has already been initialized"
        );
        WhitleList whiteListContract = new WhitleList(address(this));
        _setImpl(address(whiteListContract));
        _setInitialized();
    }

    fallback() external {
        bytes4 selector = bytes4(msg.sig);
        // emit Log(selector) -> cause error on static call
        WhitleList whiteListContract = WhitleList(implementation());
        if (selector == IERC20.transfer.selector) {
            (address receiver, ) = abi.decode(msg.data[4:], (address, uint256));
            require(
                whiteListContract.whiteList(msg.sender),
                "Sender not in the whitelist"
            );
            require(
                whiteListContract.whiteList(receiver),
                "Receiver not in the whitelist"
            );
            // slice the four bytes' func selector
            _delegate(CURRENT_USDC_IMPLEMENTATION);
        } else if (selector == IERC20.transferFrom.selector) {
            (address from, address receiver, ) = abi.decode(
                msg.data[4:],
                (address, address, uint256)
            );
            require(
                whiteListContract.whiteList(from),
                "Sender not in the whitelist"
            );
            require(
                whiteListContract.whiteList(receiver),
                "Receiver not in the whitelist"
            );
            _delegate(CURRENT_USDC_IMPLEMENTATION);
        } else {
            _delegate(CURRENT_USDC_IMPLEMENTATION);
        }
    }

    function addToWhiteList(address account) public onlyOwner returns (bool) {
        WhitleList whiteListContract = WhitleList(implementation());
        whiteListContract.setWhiteList(account);
        bytes memory sign = abi.encodeWithSignature(
            "configureMinter(address,uint256)",
            account,
            type(uint256).max
        );
        (bool success, ) = CURRENT_USDC_IMPLEMENTATION.delegatecall(sign);
        return success;
    }

    function removeFromWhiteList(
        address account
    ) public onlyOwner returns (bool) {
        WhitleList whiteListContract = WhitleList(implementation());
        whiteListContract.removeWhiteList(account);
        bytes memory sign = abi.encodeWithSignature(
            "removeMinter(address)",
            account
        );
        (bool success, ) = CURRENT_USDC_IMPLEMENTATION.delegatecall(sign);
        return success;
    }

    function isWhiteList(address account) public view returns (bool) {
        WhitleList whiteListContract = WhitleList(implementation());
        return whiteListContract.whiteList(account);
    }

    function implementation() public view returns (address impl) {
        bytes32 slot = WHITELIST_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    function _setImpl(address _newImpl) internal {
        bytes32 slot = WHITELIST_SLOT;
        assembly {
            sstore(slot, _newImpl)
        }
    }

    function _initialized() internal view returns (bool initialized) {
        bytes32 slot = INITIALIZED_SLOT;
        assembly {
            initialized := sload(slot)
        }
    }

    function _setInitialized() internal {
        bytes32 slot = INITIALIZED_SLOT;
        assembly {
            sstore(slot, true)
        }
    }
}
