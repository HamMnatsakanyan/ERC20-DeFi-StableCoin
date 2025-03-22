// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {

    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dscToken;
    HelperConfig helperConfig;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dscToken, dscEngine, helperConfig) = deployer.run();
        (,,wbtc, weth,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dscEngine, dscToken, helperConfig);
        targetContract(address(handler));
    }

    function invariant_contractMustHaveMoreDepositedThanMinted() public view{
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
        uint256 totalDscMinted = dscToken.totalSupply();

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        assert(wethValue + wbtcValue >= totalDscMinted);
    }

    function invariant_gettersShouldNotREvert() public view {
        dscEngine.getUsdValue(weth, 1e18);
        dscEngine.getTokenAmountFromUsd(weth, 1e18);
    }

}