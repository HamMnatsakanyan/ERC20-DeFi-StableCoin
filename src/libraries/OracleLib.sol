// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__PriceFeedIsStale();
    uint256 private constant STALE_THRESHOLD = 3 hours;

    function checkPriceFeedStale(AggregatorV3Interface priceFeed) public view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = priceFeed.latestRoundData();

        uint256 timePassed = block.timestamp - updatedAt;

        if(timePassed > STALE_THRESHOLD){
            revert OracleLib__PriceFeedIsStale();
        }
    }
}