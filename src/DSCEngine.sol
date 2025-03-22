// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/Test.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

contract DSCEngine is ReentrancyGuard {
    // Errors
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__CollateralTokenIsNotAllowed();
    error DSCEngine__TokenAddressesAndPriceFeedAdressesDontMatch();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__DSCMintFailed();
    error DSCEngine__HealthFactorIsGood();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__InvalidPrice();
    error DSCEngine__PriceFeedIsStale();

    using OracleLib for AggregatorV3Interface;

    /////////////////////
    // State Variables //
    /////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PERCISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount) collateralAmount) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ////////////
    // Events //
    ////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address token, uint256 indexed amount);

    ///////////////
    // Modifiers //
    ///////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier collateralIsAllowed(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__CollateralTokenIsNotAllowed();
        }
        _;
    }

    ///////////////
    // Functions //
    ///////////////

    constructor(address[] memory collateralTokenAddresses, address[] memory priceFeedAddresses, address dscToken) {
        if (collateralTokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAdressesDontMatch();
        }

        for (uint256 i = 0; i < collateralTokenAddresses.length; i++) {
            s_priceFeeds[collateralTokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(collateralTokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscToken);
    }

    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 collateralAmount, uint256 dscAmount)
        external
    {
        depositCollateral(tokenCollateralAddress, collateralAmount);
        mintDsc(dscAmount);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        collateralIsAllowed(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += collateralAmount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, collateralAmount);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 collateralAmount, uint256 dscAmount)
        external
    {
        burnDsc(dscAmount);
        redeemCollateral(tokenCollateralAddress, collateralAmount);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, collateralAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(uint256 amountDsc) public moreThanZero(amountDsc) {
        s_dscMinted[msg.sender] += amountDsc;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDsc);
        if (!minted) {
            revert DSCEngine__DSCMintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
    }

    function liquidate(address collateralToken, address userInDebt, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 userHealthFactor = healthFactor(userInDebt);
        if (userHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsGood();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);
        uint256 bonusForLiquidation = (tokenAmountFromDebtCovered * 10) / LIQUIDATION_PERCISION;
        uint256 totalToBeSent = bonusForLiquidation + tokenAmountFromDebtCovered;

        _redeemCollateral(collateralToken, totalToBeSent, userInDebt, msg.sender);
        _burnDsc(debtToCover, userInDebt, msg.sender);

        uint256 userEndingHealthFactor = healthFactor(userInDebt);
        if (userEndingHealthFactor <= userHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getTokenAmountFromUsd(address collateralToken, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralToken]);
        (, int256 price,,,) = priceFeed.checkPriceFeedStale();
        if (price <= 0){
            revert DSCEngine__InvalidPrice();
        }

        return (amount * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function healthFactor(address user) public view returns (uint256) {
        (uint256 dscMinted, uint256 collateralValue) = getAccountInformation(user);
        if (dscMinted == 0)
            return type(uint256).max;
        
        uint256 collateralValueAdjustedForThreshold = (collateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PERCISION;
        return (collateralValueAdjustedForThreshold * PRECISION) / dscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken();
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.checkPriceFeedStale();
        if (price <= 0){
            revert DSCEngine__InvalidPrice();
        } 

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }


    function _burnDsc(uint256 amount, address userInDebt, address dscFrom) internal {
        s_dscMinted[userInDebt] -= amount;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 collateralAmount, address from, address to)
        internal
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= collateralAmount;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, collateralAmount);

        bool success = IERC20(tokenCollateralAddress).transfer(to, collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function getAccountInformation(address user) public view returns (uint256 dscMinted, uint256 collateralValue) {
        dscMinted = s_dscMinted[user];
        collateralValue = getAccountCollateralValue(user);
    }

    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 collateralValue;

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            uint256 amountInUsd = getTokenAmountFromUsd(token, amount);

            collateralValue += amountInUsd;
        }

        return collateralValue;
    }

    function getCollateralBalanceOfUser(address user, address token) public view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(address token) public view returns (address) {
        return s_priceFeeds[token];
    }

    function getUserMintedDscAmount(address user) public view returns (uint256) {
        return s_dscMinted[user];
    }

}
