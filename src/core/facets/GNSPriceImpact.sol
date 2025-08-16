// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../abstract/GNSAddressStore.sol";

import "../../interfaces/libraries/IPriceImpactUtils.sol";

import "../../libraries/PriceImpactUtils.sol";
import "../../libraries/PairsStorageUtils.sol";

/**
 * @dev Facet #4: Price impact OI windows
 */
contract GNSPriceImpact is GNSAddressStore, IPriceImpactUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IPriceImpactUtils
    function initializePriceImpact(uint48 _windowsDuration, uint48 _windowsCount) external reinitializer(5) {
        PriceImpactUtils.initializePriceImpact(_windowsDuration, _windowsCount);
    }

    /// @inheritdoc IPriceImpactUtils
    function initializeNegPnlCumulVolMultiplier(uint40 _negPnlCumulVolMultiplier) external reinitializer(17) {
        PriceImpactUtils.initializeNegPnlCumulVolMultiplier(_negPnlCumulVolMultiplier);
    }

    /// @inheritdoc IPriceImpactUtils
    function initializePairFactors(
        uint16[] calldata _pairIndices,
        uint40[] calldata _protectionCloseFactors,
        uint32[] calldata _protectionCloseFactorBlocks,
        uint40[] calldata _cumulativeFactors
    ) external reinitializer(13) {
        PriceImpactUtils.initializePairFactors(
            _pairIndices, _protectionCloseFactors, _protectionCloseFactorBlocks, _cumulativeFactors
        );
    }

    // Management Setters

    /// @inheritdoc IPriceImpactUtils
    function setPriceImpactWindowsCount(uint48 _newWindowsCount) external onlyRoles(Role.GOV, Role.GOV_EMERGENCY) {
        PriceImpactUtils.setPriceImpactWindowsCount(_newWindowsCount);
    }

    /// @inheritdoc IPriceImpactUtils
    function setPriceImpactWindowsDuration(uint48 _newWindowsDuration)
        external
        onlyRoles(Role.GOV, Role.GOV_EMERGENCY)
    {
        PriceImpactUtils.setPriceImpactWindowsDuration(_newWindowsDuration, PairsStorageUtils.pairsCount());
    }

    /// @inheritdoc IPriceImpactUtils
    function setNegPnlCumulVolMultiplier(uint40 _negPnlCumulVolMultiplier)
        external
        onlyRoles(Role.GOV, Role.GOV_EMERGENCY)
    {
        PriceImpactUtils.setNegPnlCumulVolMultiplier(_negPnlCumulVolMultiplier);
    }

    /// @inheritdoc IPriceImpactUtils
    function setProtectionCloseFactorWhitelist(address[] calldata _traders, bool[] calldata _whitelisted)
        external
        onlyRoles(Role.GOV, Role.GOV_EMERGENCY)
    {
        PriceImpactUtils.setProtectionCloseFactorWhitelist(_traders, _whitelisted);
    }

    /// @inheritdoc IPriceImpactUtils
    function setUserPriceImpact(
        address[] calldata _traders,
        uint16[] calldata _pairIndices,
        uint16[] calldata _cumulVolPriceImpactMultipliers,
        uint16[] calldata _fixedSpreadPs
    ) external onlyRoles(Role.GOV, Role.GOV_EMERGENCY) {
        PriceImpactUtils.setUserPriceImpact(_traders, _pairIndices, _cumulVolPriceImpactMultipliers, _fixedSpreadPs);
    }

    /// @inheritdoc IPriceImpactUtils
    function setPairDepths(
        uint256[] calldata _indices,
        uint128[] calldata _depthsAboveUsd,
        uint128[] calldata _depthsBelowUsd
    ) external onlyRole(Role.MANAGER) {
        PriceImpactUtils.setPairDepths(_indices, _depthsAboveUsd, _depthsBelowUsd);
    }

    /// @inheritdoc IPriceImpactUtils
    function setProtectionCloseFactors(uint16[] calldata _pairIndices, uint40[] calldata _protectionCloseFactors)
        external
        onlyRoles(Role.GOV, Role.GOV_EMERGENCY)
    {
        PriceImpactUtils.setProtectionCloseFactors(_pairIndices, _protectionCloseFactors);
    }

    /// @inheritdoc IPriceImpactUtils
    function setProtectionCloseFactorBlocks(
        uint16[] calldata _pairIndices,
        uint32[] calldata _protectionCloseFactorBlocks
    ) external onlyRoles(Role.GOV, Role.GOV_EMERGENCY) {
        PriceImpactUtils.setProtectionCloseFactorBlocks(_pairIndices, _protectionCloseFactorBlocks);
    }

    /// @inheritdoc IPriceImpactUtils
    function setCumulativeFactors(uint16[] calldata _pairIndices, uint40[] calldata _cumulativeFactors)
        external
        onlyRoles(Role.GOV_TIMELOCK, Role.GOV_EMERGENCY)
    {
        PriceImpactUtils.setCumulativeFactors(_pairIndices, _cumulativeFactors);
    }

    /// @inheritdoc IPriceImpactUtils
    function setExemptOnOpen(uint16[] calldata _pairIndices, bool[] calldata _exemptOnOpen)
        external
        onlyRoles(Role.GOV_TIMELOCK, Role.GOV_EMERGENCY)
    {
        PriceImpactUtils.setExemptOnOpen(_pairIndices, _exemptOnOpen);
    }

    /// @inheritdoc IPriceImpactUtils
    function setExemptAfterProtectionCloseFactor(
        uint16[] calldata _pairIndices,
        bool[] calldata _exemptAfterProtectionCloseFactor
    ) external onlyRoles(Role.GOV_TIMELOCK, Role.GOV_EMERGENCY) {
        PriceImpactUtils.setExemptAfterProtectionCloseFactor(_pairIndices, _exemptAfterProtectionCloseFactor);
    }

    // Interactions

    /// @inheritdoc IPriceImpactUtils
    function addPriceImpactOpenInterest(
        address _trader,
        uint32 _index,
        uint256 _oiDeltaCollateral,
        bool _open,
        bool _isPnlPositive
    ) external virtual onlySelf {
        PriceImpactUtils.addPriceImpactOpenInterest(_trader, _index, _oiDeltaCollateral, _open, _isPnlPositive);
    }

    // Getters

    /// @inheritdoc IPriceImpactUtils
    function getPriceImpactOi(uint256 _pairIndex, bool _long) external view returns (uint256 activeOi) {
        return PriceImpactUtils.getPriceImpactOi(_pairIndex, _long);
    }

    /// @inheritdoc IPriceImpactUtils
    function getTradePriceImpact(
        address _trader,
        uint256 _marketPrice,
        uint256 _pairIndex,
        bool _long,
        uint256 _tradeOpenInterestUsd,
        bool _isPnlPositive,
        bool _open,
        uint256 _lastPosIncreaseBlock,
        ITradingStorage.ContractsVersion _contractsVersion
    ) external view returns (uint256 priceImpactP, uint256 priceAfterImpact) {
        (priceImpactP, priceAfterImpact) = PriceImpactUtils.getTradePriceImpact(
            _trader,
            _marketPrice,
            _pairIndex,
            _long,
            _tradeOpenInterestUsd,
            _isPnlPositive,
            _open,
            _lastPosIncreaseBlock,
            _contractsVersion
        );
    }

    /// @inheritdoc IPriceImpactUtils
    function getPairDepth(uint256 _pairIndex) external view returns (PairDepth memory) {
        return PriceImpactUtils.getPairDepth(_pairIndex);
    }

    /// @inheritdoc IPriceImpactUtils
    function getOiWindowsSettings() external view returns (OiWindowsSettings memory) {
        return PriceImpactUtils.getOiWindowsSettings();
    }

    /// @inheritdoc IPriceImpactUtils
    function getOiWindow(uint48 _windowsDuration, uint256 _pairIndex, uint256 _windowId)
        external
        view
        returns (PairOi memory)
    {
        return PriceImpactUtils.getOiWindow(_windowsDuration, _pairIndex, _windowId);
    }

    /// @inheritdoc IPriceImpactUtils
    function getOiWindows(uint48 _windowsDuration, uint256 _pairIndex, uint256[] calldata _windowIds)
        external
        view
        returns (PairOi[] memory)
    {
        return PriceImpactUtils.getOiWindows(_windowsDuration, _pairIndex, _windowIds);
    }

    /// @inheritdoc IPriceImpactUtils
    function getPairDepths(uint256[] calldata _indices) external view returns (PairDepth[] memory) {
        return PriceImpactUtils.getPairDepths(_indices);
    }

    /// @inheritdoc IPriceImpactUtils
    function getPairFactors(uint256[] calldata _indices) external view returns (IPriceImpact.PairFactors[] memory) {
        return PriceImpactUtils.getPairFactors(_indices);
    }

    /// @inheritdoc IPriceImpactUtils
    function getNegPnlCumulVolMultiplier() external view returns (uint48) {
        return PriceImpactUtils.getNegPnlCumulVolMultiplier();
    }

    /// @inheritdoc IPriceImpactUtils
    function getProtectionCloseFactorWhitelist(address _trader) external view returns (bool) {
        return PriceImpactUtils.getProtectionCloseFactorWhitelist(_trader);
    }

    /// @inheritdoc IPriceImpactUtils
    function getUserPriceImpact(address _trader, uint256 _pairIndex)
        external
        view
        returns (IPriceImpact.UserPriceImpact memory)
    {
        return PriceImpactUtils.getUserPriceImpact(_trader, _pairIndex);
    }
}
