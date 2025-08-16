// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../../interfaces/IGNSMultiCollatDiamond.sol";
import "../../interfaces/IERC20.sol";

import "../ConstantsUtils.sol";
import "../TradingCommonUtils.sol";

/**
 *
 * @dev This is an internal utils library for position size increases
 * @dev Used by UpdatePositionSizeLifecycles internal library
 */
library IncreasePositionSizeUtils {
    /**
     * @dev Validates increase position request.
     *
     * @dev Possible inputs: collateral delta > 0 and leverage delta > 0 (increase position size by collateral delta * leverage delta)
     *                       collateral delta = 0 and leverage delta > 0 (increase trade leverage by leverage delta)
     *
     * @param _trade trade of request
     * @param _input input values
     */
    function validateRequest(
        ITradingStorage.Trade memory _trade,
        IUpdatePositionSizeUtils.IncreasePositionSizeInput memory _input
    ) internal view returns (uint256 positionSizeCollateralDelta) {
        // 1. Zero values checks
        if (
            _input.leverageDelta == 0 ||
            _input.expectedPrice == 0 ||
            _input.maxSlippageP == 0
        ) revert IUpdatePositionSizeUtils.InvalidIncreasePositionSizeInput();

        // 2. Revert if new leverage is below min leverage or above max leverage
        bool isLeverageUpdate = _input.collateralDelta == 0;
        {
            uint24 leverageToValidate = isLeverageUpdate
                ? _trade.leverage + _input.leverageDelta
                : _input.leverageDelta;
            if (
                leverageToValidate >
                _getMultiCollatDiamond().pairMaxLeverage(_trade.pairIndex) ||
                leverageToValidate <
                _getMultiCollatDiamond().pairMinLeverage(_trade.pairIndex)
            ) revert ITradingInteractionsUtils.WrongLeverage();
        }

        // 3. Make sure new position size is bigger than existing one after paying borrowing and opening fees
        positionSizeCollateralDelta = TradingCommonUtils
            .getPositionSizeCollateral(
                isLeverageUpdate
                    ? _trade.collateralAmount
                    : _input.collateralDelta,
                _input.leverageDelta
            );
        uint256 existingPositionSizeCollateral = TradingCommonUtils
            .getPositionSizeCollateral(
                _trade.collateralAmount,
                _trade.leverage
            );
        uint256 newCollateralAmount = _trade.collateralAmount +
            _input.collateralDelta;
        uint256 newLeverage = isLeverageUpdate
            ? _trade.leverage + _input.leverageDelta
            : ((existingPositionSizeCollateral + positionSizeCollateralDelta) *
                1e3) / newCollateralAmount;
        {
            uint256 borrowingFeeCollateral = TradingCommonUtils
                .getTradeBorrowingFeeCollateral(_trade);
            uint256 openingFeesCollateral = TradingCommonUtils
                .getTotalTradeFeesCollateral(
                    _trade.collateralIndex,
                    _trade.user,
                    _trade.pairIndex,
                    positionSizeCollateralDelta
                );

            uint256 newPositionSizeCollateral = existingPositionSizeCollateral +
                positionSizeCollateralDelta -
                ((borrowingFeeCollateral + openingFeesCollateral) *
                    newLeverage) /
                1e3;

            if (newPositionSizeCollateral <= existingPositionSizeCollateral)
                revert IUpdatePositionSizeUtils.NewPositionSizeSmaller();
        }

        // 4. Make sure trade stays within exposure limits
        if (
            !TradingCommonUtils.isWithinExposureLimits(
                _trade.collateralIndex,
                _trade.pairIndex,
                _trade.long,
                positionSizeCollateralDelta
            )
        ) revert ITradingInteractionsUtils.AboveExposureLimits();
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
            IUpdatePositionSizeUtils.IncreasePositionSizeValues memory values
        )
    {
        bool isLeverageUpdate = _partialTrade.collateralAmount == 0;

        // 1. Calculate position size values
        values.positionSizeCollateralDelta = TradingCommonUtils
            .getPositionSizeCollateral(
                isLeverageUpdate
                    ? _existingTrade.collateralAmount
                    : _partialTrade.collateralAmount,
                _partialTrade.leverage
            );
        values.existingPositionSizeCollateral = TradingCommonUtils
            .getPositionSizeCollateral(
                _existingTrade.collateralAmount,
                _existingTrade.leverage
            );
        values.newPositionSizeCollateral =
            values.existingPositionSizeCollateral +
            values.positionSizeCollateralDelta;

        // 2. Calculate new collateral amount and leverage
        values.newCollateralAmount =
            _existingTrade.collateralAmount +
            _partialTrade.collateralAmount;
        values.newLeverage = isLeverageUpdate
            ? _existingTrade.leverage + _partialTrade.leverage
            : (values.newPositionSizeCollateral * 1e3) /
                values.newCollateralAmount;

        // 3. Calculate price impact values
        (, values.priceAfterImpact) = TradingCommonUtils
            .getTradeOpeningPriceImpact(
                ITradingCommonUtils.TradePriceImpactInput(
                    _existingTrade,
                    _answer.price,
                    _answer.spreadP,
                    values.positionSizeCollateralDelta
                ),
                _getMultiCollatDiamond()
                    .getTradeInfo(_existingTrade.user, _existingTrade.index)
                    .contractsVersion
            );

        // 4. Calculate existing trade pnl
        values.existingPnlCollateral =
            (TradingCommonUtils.getPnlPercent(
                _existingTrade.openPrice,
                _answer.price,
                _existingTrade.long,
                _existingTrade.leverage
            ) * int256(uint256(_existingTrade.collateralAmount))) /
            100 /
            int256(ConstantsUtils.P_10);

        // 5. Calculate existing trade borrowing fee
        values.borrowingFeeCollateral = TradingCommonUtils
            .getTradeBorrowingFeeCollateral(_existingTrade);

        // 6. Calculate partial trade opening fees
        values.openingFeesCollateral = TradingCommonUtils
            .getTotalTradeFeesCollateral(
                _existingTrade.collateralIndex,
                _existingTrade.user,
                _existingTrade.pairIndex,
                values.positionSizeCollateralDelta
            );

        // 7. Charge opening fees and borrowing fees on new trade collateral amount
        values.newCollateralAmount -=
            values.borrowingFeeCollateral +
            values.openingFeesCollateral;

        // 8. Calculate new open price

        // existingPositionSizeCollateral + existingPnlCollateral can never be negative
        // Because minimum value for existingPnlCollateral is -100% of trade collateral
        // If trade is long, add pnl collateral to position size collateral
        if (_existingTrade.long) {
            values.oldPosSizePlusPnlCollateral = values.existingPnlCollateral <
                0
                ? values.existingPositionSizeCollateral -
                    uint256(values.existingPnlCollateral * -1)
                : values.existingPositionSizeCollateral +
                    uint256(values.existingPnlCollateral);
        } else {
            // If trade is short, subtract pnl collateral from position size collateral
            values.oldPosSizePlusPnlCollateral = values.existingPnlCollateral <
                0
                ? values.existingPositionSizeCollateral +
                    uint256(values.existingPnlCollateral * -1)
                : values.existingPositionSizeCollateral -
                    uint256(values.existingPnlCollateral);
        }

        values.newOpenPrice =
            (values.oldPosSizePlusPnlCollateral *
                uint256(_existingTrade.openPrice) +
                values.positionSizeCollateralDelta *
                values.priceAfterImpact) /
            (values.oldPosSizePlusPnlCollateral +
                values.positionSizeCollateralDelta);

        // 8. Calculate existing and new liq price
        values.existingLiqPrice = TradingCommonUtils.getTradeLiquidationPrice(
            _existingTrade,
            true
        );
        values.newLiqPrice = _getMultiCollatDiamond().getTradeLiquidationPrice(
            IBorrowingFees.LiqPriceInput(
                _existingTrade.collateralIndex,
                _existingTrade.user,
                _existingTrade.pairIndex,
                _existingTrade.index,
                uint64(values.newOpenPrice),
                _existingTrade.long,
                values.newCollateralAmount,
                values.newLeverage,
                false,
                _getMultiCollatDiamond().getPairLiquidationParams(
                    _existingTrade.pairIndex
                ) // new liquidation params
            )
        );
    }

    /**
     * @dev Validates callback, and returns corresponding cancel reason
     * @param _existingTrade existing trade data
     * @param _values pre-calculated useful values
     * @param _expectedPrice user expected price before callback (1e10)
     * @param _maxSlippageP maximum slippage percentage from expected price (1e3)
     */
    function validateCallback(
        ITradingStorage.Trade memory _existingTrade,
        IUpdatePositionSizeUtils.IncreasePositionSizeValues memory _values,
        ITradingCallbacks.AggregatorAnswer memory _answer,
        uint256 _expectedPrice,
        uint256 _maxSlippageP
    ) internal view returns (ITradingCallbacks.CancelReason cancelReason) {
        uint256 maxSlippage = (uint256(_expectedPrice) * _maxSlippageP) /
            100 /
            1e3;

        cancelReason = (
            _existingTrade.long
                ? _values.priceAfterImpact > _expectedPrice + maxSlippage
                : _values.priceAfterImpact < _expectedPrice - maxSlippage
        )
            ? ITradingCallbacks.CancelReason.SLIPPAGE // 1. Check price after impact is within slippage limits
            : _existingTrade.tp > 0 &&
                (
                    _existingTrade.long
                        ? _answer.price >= _existingTrade.tp
                        : _answer.price <= _existingTrade.tp
                )
            ? ITradingCallbacks.CancelReason.TP_REACHED // 2. Check TP has not been reached
            : _existingTrade.sl > 0 &&
                (
                    _existingTrade.long
                        ? _answer.price <= _existingTrade.sl
                        : _answer.price >= _existingTrade.sl
                )
            ? ITradingCallbacks.CancelReason.SL_REACHED // 3. Check SL has not been reached
            : (
                _existingTrade.long
                    ? (_answer.price <= _values.existingLiqPrice ||
                        _answer.price <= _values.newLiqPrice)
                    : (_answer.price >= _values.existingLiqPrice ||
                        _answer.price >= _values.newLiqPrice)
            )
            ? ITradingCallbacks.CancelReason.LIQ_REACHED // 4. Check current and new LIQ price not reached
            : !TradingCommonUtils.isWithinExposureLimits(
                _existingTrade.collateralIndex,
                _existingTrade.pairIndex,
                _existingTrade.long,
                _values.positionSizeCollateralDelta
            )
            ? ITradingCallbacks.CancelReason.EXPOSURE_LIMITS // 5. Check trade still within exposure limits
            : _values.newLeverage >
                _getMultiCollatDiamond().pairMaxLeverage(
                    _existingTrade.pairIndex
                )
            ? ITradingCallbacks.CancelReason.MAX_LEVERAGE
            : ITradingCallbacks.CancelReason.NONE;
    }

    /**
     * @dev Updates trade (for successful request)
     * @param _existingTrade existing trade data
     * @param _values pre-calculated useful values
     */
    function updateTradeSuccess(
        ITradingStorage.Trade memory _existingTrade,
        IUpdatePositionSizeUtils.IncreasePositionSizeValues memory _values
    ) internal {
        // 1. Send borrowing fee to vault
        TradingCommonUtils.handleTradePnl(
            _existingTrade,
            0, // collateralSentToTrader = 0
            int256(_values.borrowingFeeCollateral),
            _values.borrowingFeeCollateral
        );

        // 2. Update trade in storage
        _getMultiCollatDiamond().updateTradePosition(
            ITradingStorage.Id(_existingTrade.user, _existingTrade.index),
            uint120(_values.newCollateralAmount),
            uint24(_values.newLeverage),
            uint64(_values.newOpenPrice),
            true, // refresh liquidation params
            false
        );

        // 3. Reset trade borrowing fees to zero
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
     * @param _existingTrade existing trade data
     * @param _partialTrade partial trade data
     * @param _cancelReason cancel reason
     */
    function handleCanceled(
        ITradingStorage.Trade memory _existingTrade,
        ITradingStorage.Trade memory _partialTrade,
        ITradingCallbacks.CancelReason _cancelReason
    ) internal {
        // 1. Charge gov fee on trade (if trade exists)
        if (_cancelReason != ITradingCallbacks.CancelReason.NO_TRADE) {
            // 1.1 Distribute gov fee
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

            // 1.3 Charge gov fee to trade
            _getMultiCollatDiamond().updateTradeCollateralAmount(
                ITradingStorage.Id(_existingTrade.user, _existingTrade.index),
                _existingTrade.collateralAmount - uint120(govFeeCollateral)
            );
        }

        // 2. Send back partial collateral to trader
        TradingCommonUtils.transferCollateralTo(
            _existingTrade.collateralIndex,
            _existingTrade.user,
            _partialTrade.collateralAmount
        );
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
