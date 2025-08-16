// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../interfaces/IGNSMultiCollatDiamond.sol";
import "../interfaces/IGToken.sol";
import "../interfaces/IGNSStaking.sol";
import "../interfaces/IERC20.sol";

import "./StorageUtils.sol";
import "./AddressStoreUtils.sol";
import "./TradingCommonUtils.sol";
import "./updateLeverage/UpdateLeverageLifecycles.sol";
import "./updatePositionSize/UpdatePositionSizeLifecycles.sol";

/**
 * @dev GNSTradingCallbacks facet internal library
 */
library TradingCallbacksUtils {
    /**
     * @dev Modifier to only allow trading action when trading is activated (= revert if not activated)
     */
    modifier tradingActivated() {
        if (
            _getMultiCollatDiamond().getTradingActivated() !=
            ITradingStorage.TradingActivated.ACTIVATED
        ) revert IGeneralErrors.Paused();
        _;
    }

    /**
     * @dev Modifier to only allow trading action when trading is activated or close only (= revert if paused)
     */
    modifier tradingActivatedOrCloseOnly() {
        if (
            _getMultiCollatDiamond().getTradingActivated() ==
            ITradingStorage.TradingActivated.PAUSED
        ) revert IGeneralErrors.Paused();
        _;
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function initializeCallbacks(uint8 _vaultClosingFeeP) internal {
        updateVaultClosingFeeP(_vaultClosingFeeP);
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function updateVaultClosingFeeP(uint8 _valueP) internal {
        if (_valueP > 100) revert IGeneralErrors.AboveMax();

        _getStorage().vaultClosingFeeP = _valueP;

        emit ITradingCallbacksUtils.VaultClosingFeePUpdated(_valueP);
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function updateTreasuryAddress(address _treasury) internal {
        if (_treasury == address(0)) revert IGeneralErrors.ZeroAddress();

        // Set treasury address
        IGNSAddressStore.Addresses storage addresses = AddressStoreUtils
            .getAddresses();
        addresses.treasury = _treasury;

        emit IGNSAddressStore.AddressesUpdated(addresses);
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function claimPendingGovFees() internal {
        address treasury = AddressStoreUtils.getAddresses().treasury;

        if (treasury == address(0)) revert IGeneralErrors.ZeroAddress();

        uint8 collateralsCount = _getMultiCollatDiamond().getCollateralsCount();
        for (uint8 i = 1; i <= collateralsCount; ++i) {
            uint256 feesAmountCollateral = _getStorage().pendingGovFees[i];

            if (feesAmountCollateral > 0) {
                _getStorage().pendingGovFees[i] = 0;

                TradingCommonUtils.transferCollateralTo(
                    i,
                    treasury,
                    feesAmountCollateral,
                    false
                );

                emit ITradingCallbacksUtils.PendingGovFeesClaimed(
                    i,
                    feesAmountCollateral
                );
            }
        }
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function openTradeMarketCallback(
        ITradingCallbacks.AggregatorAnswer memory _a
    ) internal tradingActivated {
        ITradingStorage.PendingOrder memory o = _getPendingOrder(_a.orderId);

        _validatePendingOrderOpen(o);

        ITradingStorage.Trade memory t = o.trade;

        (
            uint256 priceImpactP,
            uint256 priceAfterImpact,
            ITradingCallbacks.CancelReason cancelReason
        ) = _openTradePrep(t, _a.price, _a.spreadP, o.maxSlippageP);

        t.openPrice = uint64(priceAfterImpact);

        if (cancelReason == ITradingCallbacks.CancelReason.NONE) {
            t = _registerTrade(t, o);

            uint256 collateralPriceUsd = _getCollateralPriceUsd(
                t.collateralIndex
            );
            emit ITradingCallbacksUtils.MarketExecuted(
                _a.orderId,
                t.user,
                t.index,
                t,
                true,
                _a.price,
                t.openPrice,
                TradingCommonUtils.getTradeLiquidationPrice(t, true),
                priceImpactP,
                0,
                0,
                collateralPriceUsd
            );
        } else {
            // Gov fee to pay for oracle cost
            TradingCommonUtils.updateFeeTierPoints(
                t.collateralIndex,
                t.user,
                t.pairIndex,
                0
            );
            uint256 govFeeCollateral = TradingCommonUtils
                .getMinGovFeeCollateral(t.collateralIndex, t.user, t.pairIndex);
            TradingCommonUtils.distributeExactGovFeeCollateral(
                t.collateralIndex,
                t.user,
                govFeeCollateral
            );
            TradingCommonUtils.transferCollateralTo(
                t.collateralIndex,
                t.user,
                t.collateralAmount - govFeeCollateral
            );

            emit ITradingCallbacksUtils.MarketOpenCanceled(
                _a.orderId,
                t.user,
                t.pairIndex,
                cancelReason
            );
        }
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function closeTradeMarketCallback(
        ITradingCallbacks.AggregatorAnswer memory _a
    ) internal tradingActivatedOrCloseOnly {
        ITradingStorage.PendingOrder memory o = _getPendingOrder(_a.orderId);

        _validatePendingOrderOpen(o);

        ITradingStorage.Trade memory t = _getTrade(o.trade.user, o.trade.index);
        ITradingStorage.TradeInfo memory i = _getTradeInfo(
            o.trade.user,
            o.trade.index
        );

        (uint256 priceImpactP, uint256 priceAfterImpact, ) = TradingCommonUtils
            .getTradeClosingPriceImpact(
                ITradingCommonUtils.TradePriceImpactInput(
                    t,
                    _a.price,
                    _a.spreadP,
                    TradingCommonUtils.getPositionSizeCollateral(
                        t.collateralAmount,
                        t.leverage
                    )
                )
            );

        ITradingCallbacks.CancelReason cancelReason;
        {
            uint256 expectedPrice = o.trade.openPrice;
            uint256 maxSlippage = (expectedPrice *
                (
                    i.maxSlippageP > 0
                        ? i.maxSlippageP
                        : ConstantsUtils.DEFAULT_MAX_CLOSING_SLIPPAGE_P
                )) /
                100 /
                1e3;

            // prettier-ignore
            cancelReason = !t.isOpen ? ITradingCallbacks.CancelReason.NO_TRADE
                : (
                    t.long
                        ? priceAfterImpact < expectedPrice - maxSlippage
                        : priceAfterImpact > expectedPrice + maxSlippage
                )
                ? ITradingCallbacks.CancelReason.SLIPPAGE
                : ITradingCallbacks.CancelReason.NONE;
        }

        if (cancelReason != ITradingCallbacks.CancelReason.NO_TRADE) {
            ITradingCallbacks.Values memory v;

            if (cancelReason == ITradingCallbacks.CancelReason.NONE) {
                v.profitP = TradingCommonUtils.getPnlPercent(
                    t.openPrice,
                    uint64(priceAfterImpact),
                    t.long,
                    t.leverage
                );
                v.liqPrice = TradingCommonUtils.getTradeLiquidationPrice(
                    t,
                    true
                );
                v.amountSentToTrader = _unregisterTrade(
                    t,
                    v.profitP,
                    o.orderType,
                    _a.price,
                    v.liqPrice
                );
                v.collateralPriceUsd = _getCollateralPriceUsd(
                    t.collateralIndex
                );

                emit ITradingCallbacksUtils.MarketExecuted(
                    _a.orderId,
                    t.user,
                    t.index,
                    t,
                    false,
                    _a.price,
                    priceAfterImpact,
                    v.liqPrice,
                    priceImpactP,
                    v.profitP,
                    v.amountSentToTrader,
                    v.collateralPriceUsd
                );
            } else {
                // Charge gov fee
                TradingCommonUtils.updateFeeTierPoints(
                    t.collateralIndex,
                    t.user,
                    t.pairIndex,
                    0
                );
                uint256 govFeeCollateral = TradingCommonUtils
                    .getMinGovFeeCollateral(
                        t.collateralIndex,
                        t.user,
                        t.pairIndex
                    );
                TradingCommonUtils.distributeExactGovFeeCollateral(
                    t.collateralIndex,
                    t.user,
                    govFeeCollateral
                );

                // Deduct from trade collateral
                _getMultiCollatDiamond().updateTradeCollateralAmount(
                    ITradingStorage.Id({user: t.user, index: t.index}),
                    t.collateralAmount - uint120(govFeeCollateral)
                );
            }
        }

        if (cancelReason != ITradingCallbacks.CancelReason.NONE) {
            emit ITradingCallbacksUtils.MarketCloseCanceled(
                _a.orderId,
                t.user,
                t.pairIndex,
                t.index,
                cancelReason
            );
        }
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function executeTriggerOpenOrderCallback(
        ITradingCallbacks.AggregatorAnswer memory _a
    ) internal tradingActivated {
        ITradingStorage.PendingOrder memory o = _getPendingOrder(_a.orderId);

        _validatePendingOrderOpen(o);

        // Ensure state conditions for executing open order trigger are met
        (
            ITradingStorage.Trade memory t,
            ITradingCallbacks.CancelReason cancelReason,
            ITradingCallbacks.Values memory v
        ) = validateTriggerOpenOrderCallback(
                ITradingStorage.Id({user: o.trade.user, index: o.trade.index}),
                o.orderType,
                _a.open,
                _a.high,
                _a.low
            );

        if (cancelReason == ITradingCallbacks.CancelReason.NONE) {
            // Unregister open order
            v.limitIndex = t.index;
            _getMultiCollatDiamond().closeTrade(
                ITradingStorage.Id({user: t.user, index: v.limitIndex}),
                false
            );

            // Store trade
            t.openPrice = uint64(v.executionPrice);
            t.tradeType = ITradingStorage.TradeType.TRADE;
            t = _registerTrade(t, o);

            v.liqPrice = TradingCommonUtils.getTradeLiquidationPrice(t, true);
            v.collateralPriceUsd = _getCollateralPriceUsd(t.collateralIndex);

            emit ITradingCallbacksUtils.LimitExecuted(
                _a.orderId,
                t.user,
                t.index,
                v.limitIndex,
                t,
                o.user,
                o.orderType,
                v.oraclePrice,
                t.openPrice,
                v.liqPrice,
                v.priceImpactP,
                0,
                0,
                v.collateralPriceUsd,
                v.exactExecution
            );
        } else {
            emit ITradingCallbacksUtils.TriggerOrderCanceled(
                _a.orderId,
                o.user,
                o.orderType,
                cancelReason
            );
        }
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function executeTriggerCloseOrderCallback(
        ITradingCallbacks.AggregatorAnswer memory _a
    ) internal tradingActivatedOrCloseOnly {
        ITradingStorage.PendingOrder memory o = _getPendingOrder(_a.orderId);

        _validatePendingOrderOpen(o);

        // Ensure state conditions for executing close order trigger are met
        (
            ITradingStorage.Trade memory t,
            ITradingCallbacks.CancelReason cancelReason,
            ITradingCallbacks.Values memory v
        ) = validateTriggerCloseOrderCallback(
                ITradingStorage.Id({user: o.trade.user, index: o.trade.index}),
                o.orderType,
                _a.open,
                _a.high,
                _a.low
            );

        if (cancelReason == ITradingCallbacks.CancelReason.NONE) {
            v.profitP = TradingCommonUtils.getPnlPercent(
                t.openPrice,
                uint64(v.executionPrice),
                t.long,
                t.leverage
            );
            v.amountSentToTrader = _unregisterTrade(
                t,
                v.profitP,
                o.orderType,
                v.oraclePrice,
                v.liqPrice
            );
            v.collateralPriceUsd = _getCollateralPriceUsd(t.collateralIndex);

            emit ITradingCallbacksUtils.LimitExecuted(
                _a.orderId,
                t.user,
                t.index,
                0,
                t,
                o.user,
                o.orderType,
                v.oraclePrice,
                v.executionPrice,
                v.liqPrice,
                v.priceImpactP,
                v.profitP,
                v.amountSentToTrader,
                v.collateralPriceUsd,
                v.exactExecution
            );
        } else {
            emit ITradingCallbacksUtils.TriggerOrderCanceled(
                _a.orderId,
                o.user,
                o.orderType,
                cancelReason
            );
        }
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function updateLeverageCallback(
        ITradingCallbacks.AggregatorAnswer memory _a
    ) internal tradingActivated {
        ITradingStorage.PendingOrder memory order = _getMultiCollatDiamond()
            .getPendingOrder(_a.orderId);

        _validatePendingOrderOpen(order);

        UpdateLeverageLifecycles.executeUpdateLeverage(order, _a);
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function increasePositionSizeMarketCallback(
        ITradingCallbacks.AggregatorAnswer memory _a
    ) internal tradingActivated {
        ITradingStorage.PendingOrder memory order = _getMultiCollatDiamond()
            .getPendingOrder(_a.orderId);

        _validatePendingOrderOpen(order);

        UpdatePositionSizeLifecycles.executeIncreasePositionSizeMarket(
            order,
            _a
        );
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function decreasePositionSizeMarketCallback(
        ITradingCallbacks.AggregatorAnswer memory _a
    ) internal tradingActivatedOrCloseOnly {
        ITradingStorage.PendingOrder memory order = _getMultiCollatDiamond()
            .getPendingOrder(_a.orderId);

        _validatePendingOrderOpen(order);

        UpdatePositionSizeLifecycles.executeDecreasePositionSizeMarket(
            order,
            _a
        );
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function getVaultClosingFeeP() internal view returns (uint8) {
        return _getStorage().vaultClosingFeeP;
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function getPendingGovFeesCollateral(
        uint8 _collateralIndex
    ) internal view returns (uint256) {
        return _getStorage().pendingGovFees[_collateralIndex];
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function validateTriggerOpenOrderCallback(
        ITradingStorage.Id memory _tradeId,
        ITradingStorage.PendingOrderType _orderType,
        uint64 _open,
        uint64 _high,
        uint64 _low
    )
        internal
        view
        returns (
            ITradingStorage.Trade memory t,
            ITradingCallbacks.CancelReason cancelReason,
            ITradingCallbacks.Values memory v
        )
    {
        if (
            _orderType != ITradingStorage.PendingOrderType.LIMIT_OPEN &&
            _orderType != ITradingStorage.PendingOrderType.STOP_OPEN
        ) {
            revert IGeneralErrors.WrongOrderType();
        }

        t = _getTrade(_tradeId.user, _tradeId.index);

        // Return early if trade is not open
        if (!t.isOpen) {
            cancelReason = ITradingCallbacks.CancelReason.NO_TRADE;
            return (t, cancelReason, v);
        }

        v.exactExecution = (_high >= t.openPrice && _low <= t.openPrice);
        v.oraclePrice = v.exactExecution ? t.openPrice : _open;

        (v.priceImpactP, v.executionPrice, cancelReason) = _openTradePrep(
            t,
            v.oraclePrice,
            _getMultiCollatDiamond().pairSpreadP(t.user, t.pairIndex),
            _getTradeInfo(t.user, t.index).maxSlippageP
        );

        if (
            !v.exactExecution &&
            (
                t.tradeType == ITradingStorage.TradeType.STOP
                    ? (t.long ? _open < t.openPrice : _open > t.openPrice)
                    : (t.long ? _open > t.openPrice : _open < t.openPrice)
            )
        ) cancelReason = ITradingCallbacks.CancelReason.NOT_HIT;
    }

    /**
     * @dev Check ITradingCallbacksUtils interface for documentation
     */
    function validateTriggerCloseOrderCallback(
        ITradingStorage.Id memory _tradeId,
        ITradingStorage.PendingOrderType _orderType,
        uint64 _open,
        uint64 _high,
        uint64 _low
    )
        internal
        view
        returns (
            ITradingStorage.Trade memory t,
            ITradingCallbacks.CancelReason cancelReason,
            ITradingCallbacks.Values memory v
        )
    {
        if (
            _orderType != ITradingStorage.PendingOrderType.TP_CLOSE &&
            _orderType != ITradingStorage.PendingOrderType.SL_CLOSE &&
            _orderType != ITradingStorage.PendingOrderType.LIQ_CLOSE
        ) {
            revert IGeneralErrors.WrongOrderType();
        }

        t = _getTrade(_tradeId.user, _tradeId.index);
        ITradingStorage.TradeInfo memory i = _getTradeInfo(
            _tradeId.user,
            _tradeId.index
        );

        cancelReason = !t.isOpen
            ? ITradingCallbacks.CancelReason.NO_TRADE
            : ITradingCallbacks.CancelReason.NONE;

        // Return early if trade is not open
        if (cancelReason != ITradingCallbacks.CancelReason.NONE)
            return (t, cancelReason, v);

        v.liqPrice = TradingCommonUtils.getTradeLiquidationPrice(t, true);
        uint256 triggerPrice = _orderType ==
            ITradingStorage.PendingOrderType.TP_CLOSE
            ? t.tp
            : (
                _orderType == ITradingStorage.PendingOrderType.SL_CLOSE
                    ? t.sl
                    : v.liqPrice
            );

        v.exactExecution =
            triggerPrice > 0 &&
            _low <= triggerPrice &&
            _high >= triggerPrice;
        v.oraclePrice = v.exactExecution ? triggerPrice : _open;

        // Apply closing spread and price impact for TPs and SLs, not liquidations (because trade value is 0 already)
        if (_orderType != ITradingStorage.PendingOrderType.LIQ_CLOSE) {
            (v.priceImpactP, v.executionPrice, ) = TradingCommonUtils
                .getTradeClosingPriceImpact(
                    ITradingCommonUtils.TradePriceImpactInput(
                        t,
                        v.oraclePrice,
                        _getMultiCollatDiamond().pairSpreadP(
                            t.user,
                            t.pairIndex
                        ),
                        TradingCommonUtils.getPositionSizeCollateral(
                            t.collateralAmount,
                            t.leverage
                        )
                    )
                );
        } else {
            v.executionPrice = v.oraclePrice;
        }

        uint256 maxSlippage = (triggerPrice *
            (
                i.maxSlippageP > 0
                    ? i.maxSlippageP
                    : ConstantsUtils.DEFAULT_MAX_CLOSING_SLIPPAGE_P
            )) /
            100 /
            1e3;

        cancelReason = (v.exactExecution ||
            (_orderType == ITradingStorage.PendingOrderType.LIQ_CLOSE &&
                (t.long ? _open <= v.liqPrice : _open >= v.liqPrice)) ||
            (_orderType == ITradingStorage.PendingOrderType.TP_CLOSE &&
                t.tp > 0 &&
                (t.long ? _open >= t.tp : _open <= t.tp)) ||
            (_orderType == ITradingStorage.PendingOrderType.SL_CLOSE &&
                t.sl > 0 &&
                (t.long ? _open <= t.sl : _open >= t.sl)))
            ? (
                _orderType != ITradingStorage.PendingOrderType.LIQ_CLOSE &&
                    (
                        t.long
                            ? v.executionPrice < triggerPrice - maxSlippage
                            : v.executionPrice > triggerPrice + maxSlippage
                    )
                    ? ITradingCallbacks.CancelReason.SLIPPAGE
                    : ITradingCallbacks.CancelReason.NONE
            )
            : ITradingCallbacks.CancelReason.NOT_HIT;
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_TRADING_CALLBACKS_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage()
        internal
        pure
        returns (ITradingCallbacks.TradingCallbacksStorage storage s)
    {
        uint256 storageSlot = _getSlot();
        assembly {
            s.slot := storageSlot
        }
    }

    /**
     * @dev Returns current address as multi-collateral diamond interface to call other facets functions.
     */
    function _getMultiCollatDiamond()
        internal
        view
        returns (IGNSMultiCollatDiamond)
    {
        return IGNSMultiCollatDiamond(address(this));
    }

    /**
     * @dev Registers a trade in storage, and handles all fees and rewards
     * @param _trade Trade to register
     * @param _pendingOrder Corresponding pending order
     * @return Final registered trade
     */
    function _registerTrade(
        ITradingStorage.Trade memory _trade,
        ITradingStorage.PendingOrder memory _pendingOrder
    ) internal returns (ITradingStorage.Trade memory) {
        // 1. Deduct gov fee, GNS staking fee (previously dev fee), Market/Limit fee
        _trade.collateralAmount -= uint120(
            TradingCommonUtils.processFees(
                _trade,
                TradingCommonUtils.getPositionSizeCollateral(
                    _trade.collateralAmount,
                    _trade.leverage
                ),
                _pendingOrder.orderType
            )
        );

        // 2. Store final trade in storage contract
        ITradingStorage.TradeInfo memory tradeInfo;
        _trade = _getMultiCollatDiamond().storeTrade(_trade, tradeInfo);

        return _trade;
    }

    /**
     * @dev Unregisters a trade from storage, and handles all fees and rewards
     * @param _trade Trade to unregister
     * @param _profitP Profit percentage (1e10)
     * @param _orderType pending order type
     * @param _oraclePrice oracle price without closing spread/impact (1e10)
     * @param _liqPrice trade liquidation price (1e10)
     * @return tradeValueCollateral Amount of collateral sent to trader, collateral + pnl (collateral precision)
     */
    function _unregisterTrade(
        ITradingStorage.Trade memory _trade,
        int256 _profitP,
        ITradingStorage.PendingOrderType _orderType,
        uint256 _oraclePrice,
        uint256 _liqPrice
    ) internal returns (uint256 tradeValueCollateral) {
        // 1. Process closing fees, fill 'v' with closing/trigger fees and collateral left in storage, to avoid stack too deep
        uint256 totalFeesCollateral = TradingCommonUtils.processFees(
            _trade,
            TradingCommonUtils.getPositionSizeCollateral(
                _trade.collateralAmount,
                _trade.leverage
            ),
            _orderType
        );

        // 2.1 Calculate borrowing fee and net trade value (with pnl and after all closing/holding fees)
        uint256 borrowingFeeCollateral;
        (tradeValueCollateral, borrowingFeeCollateral) = TradingCommonUtils
            .getTradeValueCollateral(
                _trade,
                _profitP,
                totalFeesCollateral,
                _getMultiCollatDiamond()
                    .getCollateral(_trade.collateralIndex)
                    .precisionDelta
            );

        // 2.2 If trade is liquidated, set trade value to 0
        tradeValueCollateral = (
            _trade.long ? _oraclePrice <= _liqPrice : _oraclePrice >= _liqPrice
        )
            ? 0
            : tradeValueCollateral;

        // 3. Take collateral from vault if winning trade or send collateral to vault if losing trade
        TradingCommonUtils.handleTradePnl(
            _trade,
            int256(tradeValueCollateral),
            int256(
                _trade.collateralAmount >= totalFeesCollateral
                    ? _trade.collateralAmount - totalFeesCollateral
                    : _trade.collateralAmount // fees only charged when collateral enough to pay (due to min fee)
            ),
            borrowingFeeCollateral
        );

        // 4. Unregister trade from storage
        _getMultiCollatDiamond().closeTrade(
            ITradingStorage.Id({user: _trade.user, index: _trade.index}),
            _profitP > 0
        );
    }

    /**
     * @dev Makes pre-trade checks: price impact, if trade should be cancelled based on parameters like: PnL, leverage, slippage, etc.
     * @param _trade trade input
     * @param _executionPrice execution price (1e10 precision)
     * @param _spreadP spread % (1e10 precision)
     * @param _maxSlippageP max slippage % (1e3 precision)
     */
    function _openTradePrep(
        ITradingStorage.Trade memory _trade,
        uint256 _executionPrice,
        uint256 _spreadP,
        uint256 _maxSlippageP
    )
        internal
        view
        returns (
            uint256 priceImpactP,
            uint256 priceAfterImpact,
            ITradingCallbacks.CancelReason cancelReason
        )
    {
        uint256 positionSizeCollateral = TradingCommonUtils
            .getPositionSizeCollateral(
                _trade.collateralAmount,
                _trade.leverage
            );

        (priceImpactP, priceAfterImpact) = TradingCommonUtils
            .getTradeOpeningPriceImpact(
                ITradingCommonUtils.TradePriceImpactInput(
                    _trade,
                    _executionPrice,
                    _spreadP,
                    positionSizeCollateral
                ),
                _getMultiCollatDiamond().getCurrentContractsVersion()
            );

        uint256 maxSlippage = (uint256(_trade.openPrice) * _maxSlippageP) /
            100 /
            1e3;

        // prettier-ignore
        cancelReason =
                (
                    _trade.long
                        ? priceAfterImpact > _trade.openPrice + maxSlippage
                        : priceAfterImpact < _trade.openPrice - maxSlippage
                )
                    ? ITradingCallbacks.CancelReason.SLIPPAGE
                    : (_trade.tp > 0 && (_trade.long ? priceAfterImpact >= _trade.tp : priceAfterImpact <= _trade.tp))
                    ? ITradingCallbacks.CancelReason.TP_REACHED
                    : (_trade.sl > 0 && (_trade.long ? _executionPrice <= _trade.sl : _executionPrice >= _trade.sl))
                    ? ITradingCallbacks.CancelReason.SL_REACHED
                    : !TradingCommonUtils.isWithinExposureLimits(
                        _trade.collateralIndex,
                        _trade.pairIndex,
                        _trade.long,
                        positionSizeCollateral
                    )
                    ? ITradingCallbacks.CancelReason.EXPOSURE_LIMITS
                    : (priceImpactP * _trade.leverage) / 1e3 > ConstantsUtils.MAX_OPEN_NEGATIVE_PNL_P
                    ? ITradingCallbacks.CancelReason.PRICE_IMPACT
                    : _trade.leverage > _getMultiCollatDiamond().pairMaxLeverage(_trade.pairIndex)
                    ? ITradingCallbacks.CancelReason.MAX_LEVERAGE
                    : ITradingCallbacks.CancelReason.NONE
            ;
    }

    /**
     * @dev Reverts if pending order is not open
     * @param _order Pending order
     */
    function _validatePendingOrderOpen(
        ITradingStorage.PendingOrder memory _order
    ) internal pure {
        if (!_order.isOpen) revert ITradingCallbacksUtils.PendingOrderNotOpen();
    }

    /**
     * @dev Returns pending order from storage
     * @param _orderId Order ID
     * @return Pending order
     */
    function _getPendingOrder(
        ITradingStorage.Id memory _orderId
    ) internal view returns (ITradingStorage.PendingOrder memory) {
        return _getMultiCollatDiamond().getPendingOrder(_orderId);
    }

    /**
     * @dev Returns collateral price in USD
     * @param _collateralIndex Collateral index
     * @return Collateral price in USD
     */
    function _getCollateralPriceUsd(
        uint8 _collateralIndex
    ) internal view returns (uint256) {
        return _getMultiCollatDiamond().getCollateralPriceUsd(_collateralIndex);
    }

    /**
     * @dev Returns trade from storage
     * @param _trader Trader address
     * @param _index Trade index
     * @return Trade
     */
    function _getTrade(
        address _trader,
        uint32 _index
    ) internal view returns (ITradingStorage.Trade memory) {
        return _getMultiCollatDiamond().getTrade(_trader, _index);
    }

    /**
     * @dev Returns trade info from storage
     * @param _trader Trader address
     * @param _index Trade index
     * @return TradeInfo
     */
    function _getTradeInfo(
        address _trader,
        uint32 _index
    ) internal view returns (ITradingStorage.TradeInfo memory) {
        return _getMultiCollatDiamond().getTradeInfo(_trader, _index);
    }
}
