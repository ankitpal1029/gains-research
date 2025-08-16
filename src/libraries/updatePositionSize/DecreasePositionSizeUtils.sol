// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../../interfaces/IGNSMultiCollatDiamond.sol";
import "../../interfaces/IERC20.sol";

import "../ConstantsUtils.sol";
import "../TradingCommonUtils.sol";

/**
 *
 * @dev This is an internal utils library for position size decreases
 * @dev Used by UpdatePositionSizeLifecycles internal library
 */
library DecreasePositionSizeUtils {
    /**
     * @dev Validates decrease position size request
     *
     * @dev Possible inputs: collateral delta > 0 and leverage delta = 0 (decrease collateral by collateral delta)
     *                       collateral delta = 0 and leverage delta > 0 (decrease leverage by leverage delta)
     *
     *  @param _trade trade of request
     *  @param _input input values
     */
    function validateRequest(
        ITradingStorage.Trade memory _trade,
        IUpdatePositionSizeUtils.DecreasePositionSizeInput memory _input
    ) internal view returns (uint256 positionSizeCollateralDelta) {
        // 1. Revert if both collateral and leverage are zero or if both are non-zero
        if (
            (_input.collateralDelta == 0 && _input.leverageDelta == 0) ||
            (_input.collateralDelta > 0 && _input.leverageDelta > 0)
        ) revert IUpdatePositionSizeUtils.InvalidDecreasePositionSizeInput();

        // 2. If we update the leverage, check new leverage is above the minimum
        bool isLeverageUpdate = _input.leverageDelta > 0;
        if (
            isLeverageUpdate &&
            _trade.leverage - _input.leverageDelta <
            _getMultiCollatDiamond().pairMinLeverage(_trade.pairIndex)
        ) revert ITradingInteractionsUtils.WrongLeverage();

        // 3. Make sure new trade collateral is enough to pay borrowing fees and closing fees
        positionSizeCollateralDelta = TradingCommonUtils
            .getPositionSizeCollateral(
                isLeverageUpdate
                    ? _trade.collateralAmount
                    : _input.collateralDelta,
                isLeverageUpdate ? _input.leverageDelta : _trade.leverage
            );

        uint256 newCollateralAmount = _trade.collateralAmount -
            _input.collateralDelta;
        uint256 borrowingFeeCollateral = TradingCommonUtils
            .getTradeBorrowingFeeCollateral(_trade);
        uint256 closingFeesCollateral = TradingCommonUtils
            .getTotalTradeFeesCollateral(
                _trade.collateralIndex,
                _trade.user,
                _trade.pairIndex,
                positionSizeCollateralDelta
            );

        if (
            newCollateralAmount <=
            borrowingFeeCollateral + closingFeesCollateral
        ) revert ITradingInteractionsUtils.InsufficientCollateral();

        // 4. Revert if expected price is zero
        if (_input.expectedPrice == 0) revert IGeneralErrors.ZeroValue();
    }

    /**
     * @dev Calculates values for callback
     * @param _existingTrade existing trade data
     * @param _partialTrade partial trade data
     * @param _answer price aggregator answer
     */
    function prepareCallbackValues(
        ITradingStorage.Trade memory _existingTrade,
        ITradingStorage.Trade memory _partialTrade,
        ITradingCallbacks.AggregatorAnswer memory _answer
    )
        internal
        view
        returns (
            IUpdatePositionSizeUtils.DecreasePositionSizeValues memory values
        )
    {
        // 1. Calculate position size delta and existing position size
        bool isLeverageUpdate = _partialTrade.leverage > 0;
        values.positionSizeCollateralDelta = TradingCommonUtils
            .getPositionSizeCollateral(
                isLeverageUpdate
                    ? _existingTrade.collateralAmount
                    : _partialTrade.collateralAmount,
                isLeverageUpdate
                    ? _partialTrade.leverage
                    : _existingTrade.leverage
            );
        values.existingPositionSizeCollateral = TradingCommonUtils
            .getPositionSizeCollateral(
                _existingTrade.collateralAmount,
                _existingTrade.leverage
            );

        // 2. Calculate existing trade liquidation price
        values.existingLiqPrice = TradingCommonUtils.getTradeLiquidationPrice(
            _existingTrade,
            true
        );

        // 2.1 Apply spread and price impact to answer.price
        (, values.priceAfterImpact, ) = TradingCommonUtils
            .getTradeClosingPriceImpact(
                ITradingCommonUtils.TradePriceImpactInput(
                    _existingTrade,
                    _answer.price,
                    _answer.spreadP,
                    values.positionSizeCollateralDelta
                )
            );

        // 3. Calculate existing trade pnl
        values.existingPnlCollateral =
            (TradingCommonUtils.getPnlPercent(
                _existingTrade.openPrice,
                uint64(values.priceAfterImpact),
                _existingTrade.long,
                _existingTrade.leverage
            ) * int256(uint256(_existingTrade.collateralAmount))) /
            100 /
            int256(ConstantsUtils.P_10);

        // 4. Calculate existing trade borrowing fee
        values.borrowingFeeCollateral = TradingCommonUtils
            .getTradeBorrowingFeeCollateral(_existingTrade);

        // 5. Calculate partial trade closing fees
        values.closingFeeCollateral = TradingCommonUtils
            .getTotalTradeFeesCollateral(
                _existingTrade.collateralIndex,
                _existingTrade.user,
                _existingTrade.pairIndex,
                values.positionSizeCollateralDelta
            );

        // 5. Calculate final collateral delta
        // Collateral delta = value to send to trader after position size is decreased
        int256 partialTradePnlCollateral = (values.existingPnlCollateral *
            int256(values.positionSizeCollateralDelta)) /
            int256(values.existingPositionSizeCollateral);

        values.availableCollateralInDiamond =
            int256(uint256(_partialTrade.collateralAmount)) -
            int256(values.closingFeeCollateral);

        values.collateralSentToTrader =
            values.availableCollateralInDiamond +
            partialTradePnlCollateral -
            int256(values.borrowingFeeCollateral);

        // 7. Calculate new collateral amount and leverage
        values.newCollateralAmount =
            _existingTrade.collateralAmount -
            _partialTrade.collateralAmount;
        values.newLeverage = _existingTrade.leverage - _partialTrade.leverage;
    }

    /**
     * @dev Validates callback, and returns corresponding cancel reason
     * @param _values pre-calculated useful values
     */
    function validateCallback(
        ITradingStorage.Trade memory _existingTrade,
        ITradingStorage.PendingOrder memory _pendingOrder,
        IUpdatePositionSizeUtils.DecreasePositionSizeValues memory _values,
        ITradingCallbacks.AggregatorAnswer memory _answer
    ) internal view returns (ITradingCallbacks.CancelReason) {
        uint256 expectedPrice = _pendingOrder.trade.openPrice;
        uint256 maxSlippageP = _getMultiCollatDiamond()
            .getTradeInfo(_existingTrade.user, _existingTrade.index)
            .maxSlippageP;
        uint256 maxSlippage = (expectedPrice *
            (
                maxSlippageP > 0
                    ? maxSlippageP
                    : ConstantsUtils.DEFAULT_MAX_CLOSING_SLIPPAGE_P
            )) /
            100 /
            1e3;

        return
            (
                _existingTrade.long
                    ? _answer.price <= _values.existingLiqPrice
                    : _answer.price >= _values.existingLiqPrice
            )
                ? ITradingCallbacks.CancelReason.LIQ_REACHED
                : (
                    _existingTrade.long
                        ? _values.priceAfterImpact < expectedPrice - maxSlippage
                        : _values.priceAfterImpact > expectedPrice + maxSlippage
                )
                ? ITradingCallbacks.CancelReason.SLIPPAGE
                : ITradingCallbacks.CancelReason.NONE;
    }

    /**
     * @dev Updates trade (for successful request)
     * @param _existingTrade existing trade data
     * @param _values pre-calculated useful values
     */
    function updateTradeSuccess(
        ITradingStorage.Trade memory _existingTrade,
        IUpdatePositionSizeUtils.DecreasePositionSizeValues memory _values
    ) internal {
        // 1. Handle collateral/pnl transfers
        uint256 traderDebt = TradingCommonUtils.handleTradePnl(
            _existingTrade,
            _values.collateralSentToTrader,
            _values.availableCollateralInDiamond,
            _values.borrowingFeeCollateral
        );
        _values.newCollateralAmount -= uint120(traderDebt); // eg. when fees > partial collateral

        // 2. Update trade in storage
        _getMultiCollatDiamond().updateTradePosition(
            ITradingStorage.Id(_existingTrade.user, _existingTrade.index),
            _values.newCollateralAmount,
            _values.newLeverage,
            _existingTrade.openPrice, // open price stays the same
            false, // don't refresh liquidation params
            _values.existingPnlCollateral > 0
        );

        // 3. Reset trade borrowing fee to zero
        _getMultiCollatDiamond().resetTradeBorrowingFees(
            _existingTrade.collateralIndex,
            _existingTrade.user,
            _existingTrade.pairIndex,
            _existingTrade.index,
            _existingTrade.long
        );
    }

    /**
     * @dev Handles callback canceled case (for failed request)
     * @param _existingTrade trade to update
     * @param _cancelReason cancel reason
     */
    function handleCanceled(
        ITradingStorage.Trade memory _existingTrade,
        ITradingCallbacks.CancelReason _cancelReason
    ) internal {
        if (_cancelReason != ITradingCallbacks.CancelReason.NO_TRADE) {
            // 1. Distribute gov fee
            uint256 govFeeCollateral = TradingCommonUtils
                .getMinGovFeeCollateral(
                    _existingTrade.collateralIndex,
                    _existingTrade.user,
                    _existingTrade.pairIndex
                );
            TradingCommonUtils.distributeExactGovFeeCollateral(
                _existingTrade.collateralIndex,
                _existingTrade.user,
                govFeeCollateral
            );

            // 2. Charge gov fee to trade
            _getMultiCollatDiamond().updateTradeCollateralAmount(
                ITradingStorage.Id(_existingTrade.user, _existingTrade.index),
                _existingTrade.collateralAmount - uint120(govFeeCollateral)
            );
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
}
