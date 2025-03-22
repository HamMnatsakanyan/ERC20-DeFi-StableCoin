// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Test, console} from "forge-std/Test.sol";

contract DecentralizedStablecoinTest is StdCheats, Test {
    DecentralizedStableCoin dsc;

    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    function testRevertsOnZeroMint() public {
        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.mint(address(this), 0);
    }

    function testRevertsIfBurningMoreThanMinted() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert();
        dsc.burn(101);
        vm.stopPrank();
    }

    function testRevertsZeroBurning() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert();
        dsc.burn(0);
        vm.stopPrank();
    }

}