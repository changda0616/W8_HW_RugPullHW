// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {FiatTokenV3, IMintable} from "../src/FiatTokenV3.sol";
import {IERC20} from "../src/TradingCenter.sol";
import {ProxyFiatTokenV2} from "../src/USDC/ProxyFiatTokenV2.sol";

// My Second Rug Pull
// 請假裝你是 USDC 的 Owner，嘗試升級 usdc，並完成以下功能
// 製作一個白名單
// 只有白名單內的地址可以轉帳
// 白名單內的地址可以無限 mint token
// 如果有其他想做的也可以隨時加入

contract FiatTokenV3Test is Test {
    // Owner and users
    address admin = 0x807a96288A1A408dBC13DE2b1d087d10356395d2;
    address owner = 0xFcb19e6a322b27c06842A71e8c725399f049AE3a;
    address payable USDC = payable(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address mockContract = makeAddr("mockContract");

    // Contracts    
    FiatTokenV3 proxyFiatTokenV3;

    IERC20 proxyERC20;
    ProxyFiatTokenV2 proxy;

    uint256 initialBalance = 100000 ether;
    uint256 userInitialBalance = 1 ether;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Mint(address indexed minter, address indexed to, uint256 amount);
    event MinterConfigured(address indexed minter, uint256 minterAllowedAmount);
    event MinterRemoved(address indexed oldMinter);
    event MasterMinterChanged(address indexed newMasterMinter);

    function setUp() public {
        uint256 forkId = vm.createFork(
            "RPC_URL"
        );
        vm.selectFork(forkId);
        vm.startPrank(owner);
        // 1. Owner deploys fiatTokenV3
        FiatTokenV3 fiatTokenV3 = new FiatTokenV3();

        // 2. Get the live USDC proxy contract
        proxy = ProxyFiatTokenV2(USDC);
        // 3. Assigns proxy address to have interface of ERC20
        proxyERC20 = IERC20(address(proxy));

        // Let user1 and user2 to have some initial balances of usdt and usdc
        deal(address(proxyERC20), user1, userInitialBalance);
        deal(address(proxyERC20), user2, userInitialBalance);

        vm.etch(mockContract, "");

        // 4. User approve to mockContract
        changePrank(user1);
        proxyERC20.approve(mockContract, type(uint256).max);

        changePrank(user2);
        proxyERC20.approve(mockContract, type(uint256).max);

        // 5. Upgrade to fiatTokenV3
        changePrank(admin);
        proxy.upgradeTo(address(fiatTokenV3));

        // 6. fiatTokenV3 initialize
        changePrank(owner);
        proxyFiatTokenV3 = FiatTokenV3(address(proxy));
        proxyFiatTokenV3.initialize();

        // 7. update master minter for later use
        IMintable proxyMintable = IMintable(address(proxy));
        
        vm.expectEmit(true, false, false, false);
        emit MasterMinterChanged(owner);
        proxyMintable.updateMasterMinter(owner);

        vm.stopPrank();
    }

    function testSetup() public {
        vm.startPrank(user1);
        assertEq(proxyERC20.name(), "USD Coin");
        assertEq(proxyERC20.symbol(), "USDC");
        assertEq(proxyERC20.decimals(), 6);
    }

    function testAddWhiteList() public {
        vm.startPrank(owner);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), false);

        proxyFiatTokenV3.addToWhiteList(user1);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), true);
    }

    function testRemoveWhiteList() public {
        vm.startPrank(owner);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), false);

        proxyFiatTokenV3.addToWhiteList(user1);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), true);

        proxyFiatTokenV3.removeFromWhiteList(user1);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), false);
    }

    function testAddWhiteListFail() public {
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        proxyFiatTokenV3.addToWhiteList(user2);
    }

    function testInitializeTwice() public {
        vm.startPrank(owner);
        vm.expectRevert("Contract instance has already been initialized");
        proxyFiatTokenV3.initialize();
    }

    function testTransfer() public {
        vm.startPrank(owner);
        // 1. Set user1 and user2 to be in the whitelist
        proxyFiatTokenV3.addToWhiteList(user1);
        proxyFiatTokenV3.addToWhiteList(user2);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), true);
        assertEq(proxyFiatTokenV3.isWhiteList(user2), true);

        // 2. Transfer
        changePrank(user1);
        vm.expectEmit(true, true, false, false);
        emit Transfer(user1, user2, 0.5 ether);
        bool result1 = proxyERC20.transfer(user2, 0.5 ether);

        // 3. Check balance
        assertEq(result1, true);
        assertEq(proxyERC20.balanceOf(user2), 1.5 ether);

        // 4. Remove user1 from the whitelist
        changePrank(owner);
        proxyFiatTokenV3.removeFromWhiteList(user1);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), false);

        // 5. Check if user1 can transfer or not
        changePrank(user1);
        vm.expectRevert("Sender not in the whitelist");
        bool result2 = proxyERC20.transfer(user2, 0.5 ether);
        assertEq(result2, false);
    }

    function testTransferReceiverFail() public {
        vm.startPrank(owner);

        proxyFiatTokenV3.addToWhiteList(user1);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), true);

        changePrank(user1);
        vm.expectRevert("Receiver not in the whitelist");
        proxyERC20.transfer(user2, 1 ether);
    }

    function testTransferSenderFail() public {
        vm.startPrank(owner);

        proxyFiatTokenV3.addToWhiteList(user1);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), true);

        changePrank(user2);
        vm.expectRevert("Sender not in the whitelist");
        proxyERC20.transfer(user1, 1 ether);
    }

    function testTransferFrom() public {
        vm.startPrank(owner);

        proxyFiatTokenV3.addToWhiteList(user1);
        proxyFiatTokenV3.addToWhiteList(user2);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), true);
        assertEq(proxyFiatTokenV3.isWhiteList(user2), true);

        changePrank(mockContract);
        vm.expectEmit(true, true, false, false);
        emit Transfer(user1, user2, 1 ether);

        bool result = proxyERC20.transferFrom(user1, user2, 1 ether);

        assertEq(result, true);
        assertEq(proxyERC20.balanceOf(user1), 0);
        assertEq(proxyERC20.balanceOf(user2), 2 ether);
    }

    function testTransferFromReceiverFail() public {
        vm.startPrank(owner);

        proxyFiatTokenV3.addToWhiteList(user1);
        assertEq(proxyFiatTokenV3.isWhiteList(user1), true);

        changePrank(mockContract);
        vm.expectRevert("Receiver not in the whitelist");
        proxyERC20.transferFrom(user1, user2, 1 ether);
    }

    function testTransferFromSenderFail() public {
        vm.startPrank(owner);

        proxyFiatTokenV3.addToWhiteList(user2);
        assertEq(proxyFiatTokenV3.isWhiteList(user2), true);

        changePrank(mockContract);
        vm.expectRevert("Sender not in the whitelist");
        proxyERC20.transferFrom(user1, user2, 1 ether);
    }

    function testMint() public {
        // 1. Check if user1 can mint or not
        vm.startPrank(user1);
        IMintable proxyMintable = IMintable(address(proxy));
        vm.expectRevert("FiatToken: caller is not a minter");
        proxyMintable.mint(user1, 10000 ether);
        assertEq(proxyMintable.isMinter(user1), false);
        assertEq(proxyMintable.minterAllowance(user1), 0);

        // 2. Add user1 to whitelist
        changePrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit MinterConfigured(user1, type(uint256).max);
        proxyFiatTokenV3.addToWhiteList(user1);

        assertEq(proxyFiatTokenV3.isWhiteList(user1), true);
        assertEq(proxyMintable.isMinter(user1), true);
        assertEq(proxyMintable.minterAllowance(user1), type(uint256).max);

        // 3. Mint
        changePrank(user1);
        
        vm.expectEmit(true, true, false, false);
        emit Mint(user1, user1, 10000 ether);
        proxyMintable.mint(user1, 10000 ether);
        
        assertEq(proxyERC20.balanceOf(user1), 10001 ether);

        // 4. Remove user1 from whitelist
        changePrank(owner);
        
        vm.expectEmit(true, false, false, false);
        emit MinterRemoved(user1);
        proxyFiatTokenV3.removeFromWhiteList(user1);
        
        assertEq(proxyFiatTokenV3.isWhiteList(user1), false);
        assertEq(proxyMintable.isMinter(user1), false);
        assertEq(proxyMintable.minterAllowance(user1), 0);
        vm.expectRevert("FiatToken: caller is not a minter");
        proxyMintable.mint(user1, 10000 ether);
    }
}

// Running 12 tests for test/FiatTokenV3Test.t.sol:FiatTokenV3Test
// [PASS] testAddWhiteList() (gas: 111505)
// [PASS] testAddWhiteListFail() (gas: 22609)
// [PASS] testInitializeTwice() (gas: 20410)
// [PASS] testMint() (gas: 149107)
// [PASS] testRemoveWhiteList() (gas: 92124)
// [PASS] testSetup() (gas: 37533)
// [PASS] testTransfer() (gas: 180152)
// [PASS] testTransferFrom() (gas: 223880)
// [PASS] testTransferFromReceiverFail() (gas: 122331)
// [PASS] testTransferFromSenderFail() (gas: 121439)
// [PASS] testTransferReceiverFail() (gas: 120052)
// [PASS] testTransferSenderFail() (gas: 119240)
// Test result: ok. 12 passed; 0 failed; finished in 10.85s

// | src/FiatTokenV3.sol:FiatTokenV3 contract |                 |        |        |        |         |
// |------------------------------------------|-----------------|--------|--------|--------|---------|
// | Deployment Cost                          | Deployment Size |        |        |        |         |
// | 790769                                   | 3906            |        |        |        |         |
// | Function Name                            | min             | avg    | median | max    | # calls |
// | addToWhiteList                           | 2587            | 74743  | 82744  | 85994  | 12      |
// | initialize                               | 2395            | 240883 | 260757 | 260757 | 13      |
// | isWhiteList                              | 1481            | 2293   | 1481   | 7981   | 16      |
// | removeFromWhiteList                      | 3680            | 3680   | 3680   | 3680   | 3       |


// | src/FiatTokenV3.sol:WhitleList contract |                 |       |        |       |         |
// |-----------------------------------------|-----------------|-------|--------|-------|---------|
// | Deployment Cost                         | Deployment Size |       |        |       |         |
// | 183979                                  | 999             |       |        |       |         |
// | Function Name                           | min             | avg   | median | max   | # calls |
// | removeWhiteList                         | 605             | 605   | 605    | 605   | 3       |
// | setWhiteList                            | 22706           | 23978 | 24706  | 24706 | 11      |
// | whiteList                               | 485             | 929   | 485    | 2485  | 27      |
