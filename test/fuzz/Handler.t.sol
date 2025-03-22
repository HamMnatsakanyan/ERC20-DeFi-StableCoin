// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine immutable dscEngine;
    DecentralizedStableCoin immutable dscToken;
    HelperConfig immutable helperConfig;
    address weth;
    address wbtc;
    uint256 public mintCalled = 0;
    MockV3Aggregator public ethPriceFeed;

    uint256 constant MAX_DEPOSIT = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dscToken, HelperConfig _helperConfig) {
        dscEngine = _dscEngine;
        dscToken = _dscToken;
        helperConfig = _helperConfig;
        (,,wbtc, weth,) = helperConfig.activeNetworkConfig();
        ethPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(weth));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        address collateral = getCollateralFromSeed(collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSIT);

        vm.startPrank(msg.sender);
        ERC20Mock(collateral).mint(msg.sender, amount);
        ERC20Mock(collateral).approve(address(dscEngine), amount);
        dscEngine.depositCollateral(collateral, amount);
        vm.stopPrank();
    }

    function mintDcs(uint256 amount) public {
        vm.startPrank(msg.sender);
        (uint256 dsMinted, uint256 collateralAmount) = dscEngine.getAccountInformation(msg.sender);
        uint256 maxDscToMint = (collateralAmount / 2) - dsMinted;
        if(maxDscToMint < 0) {
            return;
        }
        
        amount = bound(amount, 0, maxDscToMint);
        if(amount == 0) {
            return;
        }
        
        dscEngine.mintDsc(amount);
        vm.stopPrank();
        mintCalled++;
        console.log(mintCalled);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        vm.startPrank(msg.sender);
        address collateral = getCollateralFromSeed(collateralSeed);
        uint256 maxCollateral = dscEngine.getCollateralBalanceOfUser(msg.sender, collateral);
        amount = bound(amount, 0, maxCollateral);
        if(amount == 0) {
            return;
        }

        dscEngine.redeemCollateral(collateral, amount);
        vm.stopPrank();
    }

    function getCollateralFromSeed(uint256 seed) private view returns (address) {
        return seed % 2 == 0 ? weth : wbtc;
    }
}