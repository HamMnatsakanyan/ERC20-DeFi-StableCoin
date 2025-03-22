// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngineTest is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dscToken;
    DeployDSC deployer;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address weth;

    address public USER = makeAddr("USER");
    uint256 public constant STARTING_WETH_BALANCE = 10 ether;
    uint256 public constant DSC_MINTED_AMOUNT = 100;

    function setUp() public {
        deployer = new DeployDSC();
        (dscToken, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_WETH_BALANCE);
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 returnedValue = dscEngine.getUsdValue(weth, ethAmount);

        assertEq(expectedUsd, returnedValue);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
    }

    function testConstrucorReverts() public {
        address[] memory collateralTokens = new address[](1);
        address[] memory priceFeeds = new address[](2);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAdressesDontMatch.selector);
        new DSCEngine(collateralTokens, priceFeeds, address(dscToken));
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedAmount = 0.05 ether;
        uint256 returnedValue = dscEngine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedAmount, returnedValue);
    }

    function testRvertIfCollateralNotAllowed() public {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__CollateralTokenIsNotAllowed.selector);
        dscEngine.depositCollateral(makeAddr("NOT_ALLOWED"), 10 ether);
    }

    function testCanDepositCollateral() public depositCollateral {
        (, uint256 collateralValue) = dscEngine.getAccountInformation(USER);
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, STARTING_WETH_BALANCE);
        assertEq(expectedDepositAmount, collateralValue);

        console.log(dscEngine.healthFactor(USER));
    }

    function testMintDsc() public depositCollateralAndMint {
        (uint256 dscMinted, ) = dscEngine.getAccountInformation(USER);
        assertEq(dscMinted, DSC_MINTED_AMOUNT);
    }

    function testReedemCollateral() public depositCollateral {

        vm.prank(USER);
        dscEngine.redeemCollateral(weth, STARTING_WETH_BALANCE);
        uint256 balance = IERC20(weth).balanceOf(USER);

        assertEq(balance, STARTING_WETH_BALANCE);
    }

    function testReedemCollateralReverts() public depositCollateralAndMint {

        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.redeemCollateral(weth, STARTING_WETH_BALANCE);
    }

    function testBurnDsc() public depositCollateralAndMint {
        uint256 dscMinted = dscEngine.getUserMintedDscAmount(USER);
        vm.startPrank(USER);
        dscToken.approve(address(dscEngine), dscMinted);
        dscEngine.burnDsc(dscMinted);
        vm.stopPrank();
        uint256 dscMintedAfterBurn = dscEngine.getUserMintedDscAmount(USER);
        assertEq(dscMintedAfterBurn, 0);
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), STARTING_WETH_BALANCE);
        dscEngine.depositCollateral(weth, STARTING_WETH_BALANCE);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMint() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), STARTING_WETH_BALANCE);
        dscEngine.depositCollateralAndMintDsc(weth, STARTING_WETH_BALANCE, DSC_MINTED_AMOUNT);
        vm.stopPrank();
        _;
    }

}
