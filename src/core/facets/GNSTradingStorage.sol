// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../abstract/GNSAddressStore.sol";

import "../../interfaces/libraries/ITradingStorageUtils.sol";

import "../../libraries/TradingStorageUtils.sol";
import "../../libraries/ArrayGetters.sol";

/**
 * @dev Facet #5: Trading storage
 */
contract GNSTradingStorage is GNSAddressStore, ITradingStorageUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc ITradingStorageUtils
    function initializeTradingStorage(
        address _gns,
        address _gnsStaking,
        address[] memory _collaterals,
        address[] memory _gTokens
    ) external reinitializer(6) {
        TradingStorageUtils.initializeTradingStorage(
            _gns,
            _gnsStaking,
            _collaterals,
            _gTokens
        );
    }

    // Management Setters

    /// @inheritdoc ITradingStorageUtils
    function updateTradingActivated(
        TradingActivated _activated
    ) external onlyRoles(Role.GOV_TIMELOCK, Role.GOV_EMERGENCY) {
        TradingStorageUtils.updateTradingActivated(_activated);
    }

    /// @inheritdoc ITradingStorageUtils
    function addCollateral(
        address _collateral,
        address _gToken
    ) external onlyRole(Role.GOV_TIMELOCK) {
        TradingStorageUtils.addCollateral(_collateral, _gToken);
    }

    /// @inheritdoc ITradingStorageUtils
    function toggleCollateralActiveState(
        uint8 _collateralIndex
    ) external onlyRoles(Role.GOV_TIMELOCK, Role.GOV_EMERGENCY) {
        TradingStorageUtils.toggleCollateralActiveState(_collateralIndex);
    }

    function updateGToken(
        address _collateral,
        address _gToken
    ) external onlyRoles(Role.GOV_TIMELOCK, Role.GOV_EMERGENCY) {
        TradingStorageUtils.updateGToken(_collateral, _gToken);
    }

    // Interactions

    /// @inheritdoc ITradingStorageUtils
    function storeTrade(
        Trade memory _trade,
        TradeInfo memory _tradeInfo
    ) external virtual onlySelf returns (Trade memory) {
        return TradingStorageUtils.storeTrade(_trade, _tradeInfo);
    }

    /// @inheritdoc ITradingStorageUtils
    function updateTradeMaxClosingSlippageP(
        ITradingStorage.Id memory _tradeId,
        uint16 _maxSlippageP
    ) external virtual onlySelf {
        TradingStorageUtils.updateTradeMaxClosingSlippageP(
            _tradeId,
            _maxSlippageP
        );
    }

    /// @inheritdoc ITradingStorageUtils
    function updateTradeCollateralAmount(
        ITradingStorage.Id memory _tradeId,
        uint120 _collateralAmount
    ) external virtual onlySelf {
        TradingStorageUtils.updateTradeCollateralAmount(
            _tradeId,
            _collateralAmount
        );
    }

    /// @inheritdoc ITradingStorageUtils
    function updateTradePosition(
        ITradingStorage.Id memory _tradeId,
        uint120 _collateralAmount,
        uint24 _leverage,
        uint64 _openPrice,
        bool _isPartialIncrease,
        bool _isPnlPositive
    ) external virtual onlySelf {
        TradingStorageUtils.updateTradePosition(
            _tradeId,
            _collateralAmount,
            _leverage,
            _openPrice,
            _isPartialIncrease,
            _isPnlPositive
        );
    }

    /// @inheritdoc ITradingStorageUtils
    function updateOpenOrderDetails(
        ITradingStorage.Id memory _tradeId,
        uint64 _openPrice,
        uint64 _tp,
        uint64 _sl,
        uint16 _maxSlippageP
    ) external virtual onlySelf {
        TradingStorageUtils.updateOpenOrderDetails(
            _tradeId,
            _openPrice,
            _tp,
            _sl,
            _maxSlippageP
        );
    }

    /// @inheritdoc ITradingStorageUtils
    function updateTradeTp(
        Id memory _tradeId,
        uint64 _newTp
    ) external virtual onlySelf {
        TradingStorageUtils.updateTradeTp(_tradeId, _newTp);
    }

    /// @inheritdoc ITradingStorageUtils
    function updateTradeSl(
        Id memory _tradeId,
        uint64 _newSl
    ) external virtual onlySelf {
        TradingStorageUtils.updateTradeSl(_tradeId, _newSl);
    }

    /// @inheritdoc ITradingStorageUtils
    function closeTrade(
        Id memory _tradeId,
        bool _isPnlPositive
    ) external virtual onlySelf {
        TradingStorageUtils.closeTrade(_tradeId, _isPnlPositive);
    }

    /// @inheritdoc ITradingStorageUtils
    function storePendingOrder(
        PendingOrder memory _pendingOrder
    ) external virtual onlySelf returns (PendingOrder memory) {
        return TradingStorageUtils.storePendingOrder(_pendingOrder);
    }

    /// @inheritdoc ITradingStorageUtils
    function closePendingOrder(Id memory _orderId) external virtual onlySelf {
        TradingStorageUtils.closePendingOrder(_orderId);
    }

    // Getters

    /// @inheritdoc ITradingStorageUtils
    function getCollateral(
        uint8 _index
    ) external view returns (Collateral memory) {
        return TradingStorageUtils.getCollateral(_index);
    }

    /// @inheritdoc ITradingStorageUtils
    function isCollateralActive(uint8 _index) external view returns (bool) {
        return TradingStorageUtils.isCollateralActive(_index);
    }

    /// @inheritdoc ITradingStorageUtils
    function isCollateralListed(uint8 _index) external view returns (bool) {
        return TradingStorageUtils.isCollateralListed(_index);
    }

    /// @inheritdoc ITradingStorageUtils
    function isCollateralGns(uint8 _index) external view returns (bool) {
        return TradingStorageUtils.isCollateralGns(_index);
    }

    /// @inheritdoc ITradingStorageUtils
    function getCollateralsCount() external view returns (uint8) {
        return TradingStorageUtils.getCollateralsCount();
    }

    /// @inheritdoc ITradingStorageUtils
    function getCollaterals() external view returns (Collateral[] memory) {
        return TradingStorageUtils.getCollaterals();
    }

    /// @inheritdoc ITradingStorageUtils
    function getCollateralIndex(
        address _collateral
    ) external view returns (uint8) {
        return TradingStorageUtils.getCollateralIndex(_collateral);
    }

    /// @inheritdoc ITradingStorageUtils
    function getGnsCollateralIndex() external view returns (uint8) {
        return TradingStorageUtils.getGnsCollateralIndex();
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradingActivated() external view returns (TradingActivated) {
        return TradingStorageUtils.getTradingActivated();
    }

    /// @inheritdoc ITradingStorageUtils
    function getTraderStored(address _trader) external view returns (bool) {
        return TradingStorageUtils.getTraderStored(_trader);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradersCount() external view returns (uint256) {
        return TradingStorageUtils.getTradersCount();
    }

    /// @inheritdoc ITradingStorageUtils
    function getTraders(
        uint32 _offset,
        uint32 _limit
    ) external view returns (address[] memory) {
        return ArrayGetters.getTraders(_offset, _limit);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTrade(
        address _trader,
        uint32 _index
    ) external view returns (Trade memory) {
        return TradingStorageUtils.getTrade(_trader, _index);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTrades(address _trader) external view returns (Trade[] memory) {
        return ArrayGetters.getTrades(_trader);
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllTradesForTraders(
        address[] memory _traders,
        uint256 _offset,
        uint256 _limit
    ) external view returns (Trade[] memory) {
        return ArrayGetters.getAllTradesForTraders(_traders, _offset, _limit);
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllTrades(
        uint256 _offset,
        uint256 _limit
    ) external view returns (Trade[] memory) {
        return ArrayGetters.getAllTrades(_offset, _limit);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradeInfo(
        address _trader,
        uint32 _index
    ) external view returns (TradeInfo memory) {
        return TradingStorageUtils.getTradeInfo(_trader, _index);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradeInfos(
        address _trader
    ) external view returns (TradeInfo[] memory) {
        return ArrayGetters.getTradeInfos(_trader);
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllTradeInfosForTraders(
        address[] memory _traders,
        uint256 _offset,
        uint256 _limit
    ) external view returns (TradeInfo[] memory) {
        return
            ArrayGetters.getAllTradeInfosForTraders(_traders, _offset, _limit);
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllTradeInfos(
        uint256 _offset,
        uint256 _limit
    ) external view returns (TradeInfo[] memory) {
        return ArrayGetters.getAllTradeInfos(_offset, _limit);
    }

    /// @inheritdoc ITradingStorageUtils
    function getPendingOrder(
        Id memory _orderId
    ) external view returns (PendingOrder memory) {
        return TradingStorageUtils.getPendingOrder(_orderId);
    }

    /// @inheritdoc ITradingStorageUtils
    function getPendingOrders(
        address _user
    ) external view returns (PendingOrder[] memory) {
        return ArrayGetters.getPendingOrders(_user);
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllPendingOrdersForTraders(
        address[] memory _traders,
        uint256 _offset,
        uint256 _limit
    ) external view returns (PendingOrder[] memory) {
        return
            ArrayGetters.getAllPendingOrdersForTraders(
                _traders,
                _offset,
                _limit
            );
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllPendingOrders(
        uint256 _offset,
        uint256 _limit
    ) external view returns (PendingOrder[] memory) {
        return ArrayGetters.getAllPendingOrders(_offset, _limit);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradePendingOrderBlock(
        Id memory _tradeId,
        PendingOrderType _orderType
    ) external view returns (uint256) {
        return
            TradingStorageUtils.getTradePendingOrderBlock(_tradeId, _orderType);
    }

    /// @inheritdoc ITradingStorageUtils
    function getCounters(
        address _trader,
        CounterType _type
    ) external view returns (Counter memory) {
        return TradingStorageUtils.getCounters(_trader, _type);
    }

    /// @inheritdoc ITradingStorageUtils
    function getCountersForTraders(
        address[] calldata _traders,
        CounterType _type
    ) external view returns (Counter[] memory) {
        return ArrayGetters.getCountersForTraders(_traders, _type);
    }

    /// @inheritdoc ITradingStorageUtils
    function getGToken(uint8 _collateralIndex) external view returns (address) {
        return TradingStorageUtils.getGToken(_collateralIndex);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradeLiquidationParams(
        address _trader,
        uint32 _index
    ) external view returns (IPairsStorage.GroupLiquidationParams memory) {
        return TradingStorageUtils.getTradeLiquidationParams(_trader, _index);
    }

    /// @inheritdoc ITradingStorageUtils
    function getTradesLiquidationParams(
        address _trader
    ) external view returns (IPairsStorage.GroupLiquidationParams[] memory) {
        return ArrayGetters.getTradesLiquidationParams(_trader);
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllTradesLiquidationParamsForTraders(
        address[] memory _traders,
        uint256 _offset,
        uint256 _limit
    ) external view returns (IPairsStorage.GroupLiquidationParams[] memory) {
        return
            ArrayGetters.getAllTradesLiquidationParamsForTraders(
                _traders,
                _offset,
                _limit
            );
    }

    /// @inheritdoc ITradingStorageUtils
    function getAllTradesLiquidationParams(
        uint256 _offset,
        uint256 _limit
    ) external view returns (IPairsStorage.GroupLiquidationParams[] memory) {
        return ArrayGetters.getAllTradesLiquidationParams(_offset, _limit);
    }

    /// @inheritdoc ITradingStorageUtils
    function getCurrentContractsVersion()
        external
        pure
        returns (ITradingStorage.ContractsVersion)
    {
        return TradingStorageUtils.getCurrentContractsVersion();
    }
}
