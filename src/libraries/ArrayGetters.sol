// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./TradingStorageUtils.sol";

/**
 * @dev External library for array getters to save bytecode size in facet libraries
 */
library ArrayGetters {
    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTraders(uint32 _offset, uint32 _limit) public view returns (address[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();

        if (s.traders.length == 0) return new address[](0);

        uint256 lastIndex = s.traders.length - 1;
        _limit = _limit == 0 || _limit > lastIndex ? uint32(lastIndex) : _limit;

        address[] memory traders = new address[](_limit - _offset + 1);

        uint32 currentIndex;
        for (uint32 i = _offset; i <= _limit; ++i) {
            address trader = s.traders[i];
            if (
                s.userCounters[trader][ITradingStorage.CounterType.TRADE].openCount > 0
                    || s.userCounters[trader][ITradingStorage.CounterType.PENDING_ORDER].openCount > 0
            ) {
                traders[currentIndex++] = trader;
            }
        }

        return traders;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTrades(address _trader) public view returns (ITradingStorage.Trade[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter memory traderCounter = s.userCounters[_trader][ITradingStorage.CounterType.TRADE];
        ITradingStorage.Trade[] memory trades = new ITradingStorage.Trade[](traderCounter.openCount);

        uint32 currentIndex;
        for (uint32 i; i < traderCounter.currentIndex; ++i) {
            ITradingStorage.Trade storage trade = s.trades[_trader][i];

            if (trade.isOpen) {
                trades[currentIndex++] = trade;

                // Exit loop if all open trades have been found
                if (currentIndex == traderCounter.openCount) break;
            }
        }

        return trades;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTradesForTraders(address[] memory _traders, uint256 _offset, uint256 _limit)
        public
        view
        returns (ITradingStorage.Trade[] memory)
    {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();

        uint256 currentTradeIndex; // current global trade index
        uint256 currentArrayIndex; // current index in returned trades array

        ITradingStorage.Trade[] memory trades = new ITradingStorage.Trade[](_limit - _offset + 1);

        // Fetch all trades for each trader
        for (uint256 i; i < _traders.length; ++i) {
            // Exit loop if limit is reached
            if (currentTradeIndex > _limit) break;

            // Skip if next trader address is 0; `getTraders` can return address(0)
            address trader = _traders[i];
            if (trader == address(0)) continue;

            // Fetch trader trade counter
            ITradingStorage.Counter memory traderCounter = s.userCounters[trader][ITradingStorage.CounterType.TRADE];

            // Exit if user has no open trades
            // We check because `getTraders` also traders with pending orders
            if (traderCounter.openCount == 0) continue;

            // If current trade index + openCount is lte to offset, skip to next trader
            if (currentTradeIndex + traderCounter.openCount <= _offset) {
                currentTradeIndex += traderCounter.openCount;
                continue;
            }

            ITradingStorage.Trade[] memory traderTrades = getTrades(trader);

            // Add trader trades to final trades array only if within _offset and _limit
            for (uint256 j; j < traderTrades.length; ++j) {
                if (currentTradeIndex > _limit) break; // Exit loop if limit is reached

                // Only process trade if currentTradeIndex is >= offset
                if (currentTradeIndex >= _offset) {
                    trades[currentArrayIndex++] = traderTrades[j];
                }

                currentTradeIndex++;
            }
        }

        return trades;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTrades(uint256 _offset, uint256 _limit) external view returns (ITradingStorage.Trade[] memory) {
        // Fetch all traders with open trades (no pagination, return size is not an issue here)
        address[] memory traders = getTraders(0, 0);
        return getAllTradesForTraders(traders, _offset, _limit);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTradeInfos(address _trader) public view returns (ITradingStorage.TradeInfo[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter memory traderCounter = s.userCounters[_trader][ITradingStorage.CounterType.TRADE];
        ITradingStorage.TradeInfo[] memory tradeInfos = new ITradingStorage.TradeInfo[](traderCounter.openCount);

        uint32 currentIndex;
        for (uint32 i; i < traderCounter.currentIndex; ++i) {
            if (s.trades[_trader][i].isOpen) {
                tradeInfos[currentIndex++] = s.tradeInfos[_trader][i];

                // Exit loop if all open trade infos have been found
                if (currentIndex == traderCounter.openCount) break;
            }
        }

        return tradeInfos;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTradeInfosForTraders(address[] memory _traders, uint256 _offset, uint256 _limit)
        public
        view
        returns (ITradingStorage.TradeInfo[] memory)
    {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();

        uint256 currentTradeIndex; // current global trade index
        uint256 currentArrayIndex; // current index in returned trades array

        ITradingStorage.TradeInfo[] memory tradesInfos = new ITradingStorage.TradeInfo[](_limit - _offset + 1);

        // Fetch all trades for each trader
        for (uint256 i; i < _traders.length; ++i) {
            // Exit loop if limit is reached
            if (currentTradeIndex > _limit) break;

            // Skip if next trader address is 0; `getTraders` can return address(0)
            address trader = _traders[i];
            if (trader == address(0)) continue;

            // Fetch trader trade counter
            ITradingStorage.Counter memory traderCounter = s.userCounters[trader][ITradingStorage.CounterType.TRADE];

            // Exit if user has no open trades
            // We check because `getTraders` also traders with pending orders
            if (traderCounter.openCount == 0) continue;

            // If current trade index + openCount is lte to offset, skip to next trader
            if (currentTradeIndex + traderCounter.openCount <= _offset) {
                currentTradeIndex += traderCounter.openCount;
                continue;
            }

            ITradingStorage.TradeInfo[] memory traderTradesInfos = getTradeInfos(trader);

            // Add trader trades to final trades array only if within _offset and _limit
            for (uint256 j; j < traderTradesInfos.length; ++j) {
                if (currentTradeIndex > _limit) break; // Exit loop if limit is reached

                if (currentTradeIndex >= _offset) {
                    tradesInfos[currentArrayIndex++] = traderTradesInfos[j];
                }

                currentTradeIndex++;
            }
        }

        return tradesInfos;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTradeInfos(uint256 _offset, uint256 _limit)
        external
        view
        returns (ITradingStorage.TradeInfo[] memory)
    {
        // Fetch all traders with open trades (no pagination, return size is not an issue here)
        address[] memory traders = getTraders(0, 0);
        return getAllTradeInfosForTraders(traders, _offset, _limit);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getPendingOrders(address _trader) public view returns (ITradingStorage.PendingOrder[] memory) {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter memory traderCounter =
            s.userCounters[_trader][ITradingStorage.CounterType.PENDING_ORDER];
        ITradingStorage.PendingOrder[] memory pendingOrders =
            new ITradingStorage.PendingOrder[](traderCounter.openCount);

        uint32 currentIndex;
        for (uint32 i; i < traderCounter.currentIndex; ++i) {
            if (s.pendingOrders[_trader][i].isOpen) {
                pendingOrders[currentIndex++] = s.pendingOrders[_trader][i];

                // Exit loop if all open pending orders have been found
                if (currentIndex == traderCounter.openCount) break;
            }
        }

        return pendingOrders;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllPendingOrdersForTraders(address[] memory _traders, uint256 _offset, uint256 _limit)
        public
        view
        returns (ITradingStorage.PendingOrder[] memory)
    {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();

        uint256 currentPendingOrderIndex; // current global pending order index
        uint256 currentArrayIndex; // current index in returned pending orders array

        ITradingStorage.PendingOrder[] memory pendingOrders = new ITradingStorage.PendingOrder[](_limit - _offset + 1);

        // Fetch all trades for each trader
        for (uint256 i; i < _traders.length; ++i) {
            // Exit loop if limit is reached
            if (currentPendingOrderIndex > _limit) break;

            // Skip if next trader address is 0; `getTraders` can return address(0)
            address trader = _traders[i];
            if (trader == address(0)) continue;

            // Fetch trader trade counter
            ITradingStorage.Counter memory traderCounter =
                s.userCounters[trader][ITradingStorage.CounterType.PENDING_ORDER];

            // Exit if user has no open pending orders
            // We check because `getTraders` also traders with pending orders
            if (traderCounter.openCount == 0) continue;

            // If current trade index + openCount is lte to offset, skip to next trader
            if (currentPendingOrderIndex + traderCounter.openCount <= _offset) {
                currentPendingOrderIndex += traderCounter.openCount;
                continue;
            }

            ITradingStorage.PendingOrder[] memory traderPendingOrders = getPendingOrders(trader);

            // Add trader trades to final trades array only if within _offset and _limit
            for (uint256 j; j < traderPendingOrders.length; ++j) {
                if (currentPendingOrderIndex > _limit) break; // Exit loop if limit is reached

                if (currentPendingOrderIndex >= _offset) {
                    pendingOrders[currentArrayIndex++] = traderPendingOrders[j];
                }

                currentPendingOrderIndex++;
            }
        }

        return pendingOrders;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllPendingOrders(uint256 _offset, uint256 _limit)
        external
        view
        returns (ITradingStorage.PendingOrder[] memory)
    {
        // Fetch all traders with open trades (no pagination, return size is not an issue here)
        address[] memory traders = getTraders(0, 0);
        return getAllPendingOrdersForTraders(traders, _offset, _limit);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getTradesLiquidationParams(address _trader)
        public
        view
        returns (IPairsStorage.GroupLiquidationParams[] memory)
    {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter memory traderCounter = s.userCounters[_trader][ITradingStorage.CounterType.TRADE];
        IPairsStorage.GroupLiquidationParams[] memory tradeLiquidationParams =
            new IPairsStorage.GroupLiquidationParams[](traderCounter.openCount);

        uint32 currentIndex;
        for (uint32 i; i < traderCounter.currentIndex; ++i) {
            if (s.trades[_trader][i].isOpen) {
                tradeLiquidationParams[currentIndex++] = s.tradeLiquidationParams[_trader][i];

                // Exit loop if all open trades have been found
                if (currentIndex == traderCounter.openCount) break;
            }
        }

        return tradeLiquidationParams;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTradesLiquidationParamsForTraders(address[] memory _traders, uint256 _offset, uint256 _limit)
        public
        view
        returns (IPairsStorage.GroupLiquidationParams[] memory)
    {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();

        uint256 currentTradeLiquidationParamIndex; // current global trade liquidation params index
        uint256 currentArrayIndex; // current index in returned trade liquidation params array

        IPairsStorage.GroupLiquidationParams[] memory tradeLiquidationParams =
            new IPairsStorage.GroupLiquidationParams[](_limit - _offset + 1);

        // Fetch all trades for each trader
        for (uint256 i; i < _traders.length; ++i) {
            // Exit loop if limit is reached
            if (currentTradeLiquidationParamIndex > _limit) break;

            // Skip if next trader address is 0; `getTraders` can return address(0)
            address trader = _traders[i];
            if (trader == address(0)) continue;

            // Fetch trader trade counter
            ITradingStorage.Counter memory traderCounter = s.userCounters[trader][ITradingStorage.CounterType.TRADE];

            // Exit if user has no open trades
            // We check because `getTraders` also traders with pending orders
            if (traderCounter.openCount == 0) continue;

            // If current trade index + openCount is lte to offset, skip to next trader
            if (currentTradeLiquidationParamIndex + traderCounter.openCount <= _offset) {
                currentTradeLiquidationParamIndex += traderCounter.openCount;
                continue;
            }

            IPairsStorage.GroupLiquidationParams[] memory traderLiquidationParams = getTradesLiquidationParams(trader);

            // Add trader trades to final trades array only if within _offset and _limit
            for (uint256 j; j < traderLiquidationParams.length; ++j) {
                if (currentTradeLiquidationParamIndex > _limit) break; // Exit loop if limit is reached

                if (currentTradeLiquidationParamIndex >= _offset) {
                    tradeLiquidationParams[currentArrayIndex++] = traderLiquidationParams[j];
                }

                currentTradeLiquidationParamIndex++;
            }
        }

        return tradeLiquidationParams;
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getAllTradesLiquidationParams(uint256 _offset, uint256 _limit)
        external
        view
        returns (IPairsStorage.GroupLiquidationParams[] memory)
    {
        // Fetch all traders with open trades (no pagination, return size is not an issue here)
        address[] memory traders = getTraders(0, 0);
        return getAllTradesLiquidationParamsForTraders(traders, _offset, _limit);
    }

    /**
     * @dev Check ITradingStorageUtils interface for documentation
     */
    function getCountersForTraders(address[] calldata _traders, ITradingStorage.CounterType _counterType)
        external
        view
        returns (ITradingStorage.Counter[] memory)
    {
        ITradingStorage.TradingStorage storage s = TradingStorageUtils._getStorage();
        ITradingStorage.Counter[] memory counters = new ITradingStorage.Counter[](_traders.length);

        for (uint256 i; i < _traders.length; ++i) {
            counters[i] = s.userCounters[_traders[i]][_counterType];
        }

        return counters;
    }
}
