// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../interfaces/IGNSMultiCollatDiamond.sol";

import "./StorageUtils.sol";
import "./ConstantsUtils.sol";
import "./ChainUtils.sol";
import "./TradingCommonUtils.sol";
import "./TradingStorageUtils.sol";

/**
 * @dev GNSPriceImpact facet internal library
 *
 * This is a library to help manage a price impact decay algorithm .
 *
 * When a trade is placed, OI is added to the window corresponding to time of open.
 * When a trade is removed, OI is removed from the window corresponding to time of open.
 *
 * When calculating price impact, only the most recent X windows are taken into account.
 *
 */
library PriceImpactUtils {
    uint48 private constant MAX_WINDOWS_COUNT = 5;
    uint48 private constant MAX_WINDOWS_DURATION = 10 minutes;
    uint48 private constant MIN_WINDOWS_DURATION = 1 minutes;
    uint256 private constant MAX_PROTECTION_CLOSE_FACTOR_DURATION = 10 minutes;
    uint256 private constant MIN_NEG_PNL_CUMUL_VOL_MULTIPLIER =
        (20 * ConstantsUtils.P_10) / 100;
    uint16 private constant MAX_CUMUL_VOL_PRICE_IMPACT_MULTIPLIER = 3e3;
    uint16 private constant MAX_FIXED_SPREAD_P = 0.1e3;

    /**
     * @dev Validates new windowsDuration value
     */
    modifier validWindowsDuration(uint48 _windowsDuration) {
        if (
            _windowsDuration < MIN_WINDOWS_DURATION ||
            _windowsDuration > MAX_WINDOWS_DURATION
        ) revert IPriceImpactUtils.WrongWindowsDuration();
        _;
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function initializePriceImpact(
        uint48 _windowsDuration,
        uint48 _windowsCount
    ) internal validWindowsDuration(_windowsDuration) {
        if (_windowsCount > MAX_WINDOWS_COUNT) revert IGeneralErrors.AboveMax();

        _getStorage().oiWindowsSettings = IPriceImpact.OiWindowsSettings({
            startTs: uint48(block.timestamp),
            windowsDuration: _windowsDuration,
            windowsCount: _windowsCount
        });

        emit IPriceImpactUtils.OiWindowsSettingsInitialized(
            _windowsDuration,
            _windowsCount
        );
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function initializeNegPnlCumulVolMultiplier(
        uint40 _negPnlCumulVolMultiplier
    ) internal {
        setNegPnlCumulVolMultiplier(_negPnlCumulVolMultiplier);
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function initializePairFactors(
        uint16[] calldata _pairIndices,
        uint40[] calldata _protectionCloseFactors,
        uint32[] calldata _protectionCloseFactorBlocks,
        uint40[] calldata _cumulativeFactors
    ) internal {
        setProtectionCloseFactors(_pairIndices, _protectionCloseFactors);
        setProtectionCloseFactorBlocks(
            _pairIndices,
            _protectionCloseFactorBlocks
        );
        setCumulativeFactors(_pairIndices, _cumulativeFactors);
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setPriceImpactWindowsCount(uint48 _newWindowsCount) internal {
        IPriceImpact.OiWindowsSettings storage settings = _getStorage()
            .oiWindowsSettings;

        if (_newWindowsCount > MAX_WINDOWS_COUNT)
            revert IGeneralErrors.AboveMax();

        settings.windowsCount = _newWindowsCount;

        emit IPriceImpactUtils.PriceImpactWindowsCountUpdated(_newWindowsCount);
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setPriceImpactWindowsDuration(
        uint48 _newWindowsDuration,
        uint256 _pairsCount
    ) internal validWindowsDuration(_newWindowsDuration) {
        IPriceImpact.PriceImpactStorage
            storage priceImpactStorage = _getStorage();
        IPriceImpact.OiWindowsSettings storage settings = priceImpactStorage
            .oiWindowsSettings;

        if (settings.windowsCount > 0) {
            _transferPriceImpactOiForPairs(
                _pairsCount,
                priceImpactStorage.windows[settings.windowsDuration],
                priceImpactStorage.windows[_newWindowsDuration],
                settings,
                _newWindowsDuration
            );
        }

        settings.windowsDuration = _newWindowsDuration;

        emit IPriceImpactUtils.PriceImpactWindowsDurationUpdated(
            _newWindowsDuration
        );
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setNegPnlCumulVolMultiplier(
        uint40 _negPnlCumulVolMultiplier
    ) internal {
        if (_negPnlCumulVolMultiplier < MIN_NEG_PNL_CUMUL_VOL_MULTIPLIER)
            revert IGeneralErrors.BelowMin();
        if (_negPnlCumulVolMultiplier > ConstantsUtils.P_10)
            revert IGeneralErrors.AboveMax();

        _getStorage().negPnlCumulVolMultiplier = _negPnlCumulVolMultiplier;

        emit IPriceImpactUtils.NegPnlCumulVolMultiplierUpdated(
            _negPnlCumulVolMultiplier
        );
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setProtectionCloseFactorWhitelist(
        address[] calldata _traders,
        bool[] calldata _whitelisted
    ) internal {
        if (_traders.length != _whitelisted.length)
            revert IGeneralErrors.WrongLength();

        IPriceImpact.PriceImpactStorage storage s = _getStorage();

        for (uint256 i = 0; i < _traders.length; ++i) {
            (address trader, bool whitelisted) = (_traders[i], _whitelisted[i]);

            if (trader == address(0)) revert IGeneralErrors.ZeroAddress();

            s.protectionCloseFactorWhitelist[trader] = whitelisted;

            emit IPriceImpactUtils.ProtectionCloseFactorWhitelistUpdated(
                trader,
                whitelisted
            );
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setUserPriceImpact(
        address[] calldata _traders,
        uint16[] calldata _pairIndices,
        uint16[] calldata _cumulVolPriceImpactMultipliers,
        uint16[] calldata _fixedSpreadPs
    ) internal {
        if (
            _traders.length != _pairIndices.length ||
            _traders.length != _cumulVolPriceImpactMultipliers.length ||
            _traders.length != _fixedSpreadPs.length
        ) revert IGeneralErrors.WrongLength();

        IPriceImpact.PriceImpactStorage storage s = _getStorage();

        for (uint256 i = 0; i < _traders.length; ++i) {
            (
                address trader,
                uint16 pairIndex,
                uint16 cumulVolPriceImpactMultiplier,
                uint16 fixedSpreadP
            ) = (
                    _traders[i],
                    _pairIndices[i],
                    _cumulVolPriceImpactMultipliers[i],
                    _fixedSpreadPs[i]
                );

            if (trader == address(0)) revert IGeneralErrors.ZeroAddress();
            if (
                cumulVolPriceImpactMultiplier >
                MAX_CUMUL_VOL_PRICE_IMPACT_MULTIPLIER
            ) revert IGeneralErrors.AboveMax();
            if (fixedSpreadP > MAX_FIXED_SPREAD_P)
                revert IGeneralErrors.AboveMax();

            IPriceImpact.UserPriceImpact storage userPriceImpact = s
                .userPriceImpact[trader][pairIndex];

            userPriceImpact
                .cumulVolPriceImpactMultiplier = cumulVolPriceImpactMultiplier;
            userPriceImpact.fixedSpreadP = fixedSpreadP;

            emit IPriceImpactUtils.UserPriceImpactUpdated(
                trader,
                pairIndex,
                cumulVolPriceImpactMultiplier,
                fixedSpreadP
            );
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setPairDepths(
        uint256[] calldata _indices,
        uint128[] calldata _depthsAboveUsd,
        uint128[] calldata _depthsBelowUsd
    ) internal {
        if (
            _indices.length != _depthsAboveUsd.length ||
            _depthsAboveUsd.length != _depthsBelowUsd.length
        ) revert IGeneralErrors.WrongLength();

        IPriceImpact.PriceImpactStorage storage s = _getStorage();

        for (uint256 i = 0; i < _indices.length; ++i) {
            s.pairDepths[_indices[i]] = IPriceImpact.PairDepth({
                onePercentDepthAboveUsd: _depthsAboveUsd[i],
                onePercentDepthBelowUsd: _depthsBelowUsd[i]
            });

            emit IPriceImpactUtils.OnePercentDepthUpdated(
                _indices[i],
                _depthsAboveUsd[i],
                _depthsBelowUsd[i]
            );
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setProtectionCloseFactors(
        uint16[] calldata _pairIndices,
        uint40[] calldata _protectionCloseFactors
    ) internal {
        if (
            _pairIndices.length == 0 ||
            _protectionCloseFactors.length != _pairIndices.length
        ) revert IGeneralErrors.WrongLength();

        IPriceImpact.PriceImpactStorage storage s = _getStorage();

        for (uint256 i = 0; i < _protectionCloseFactors.length; ++i) {
            if (_protectionCloseFactors[i] < ConstantsUtils.P_10)
                revert IGeneralErrors.BelowMin();

            s
                .pairFactors[_pairIndices[i]]
                .protectionCloseFactor = _protectionCloseFactors[i];

            emit IPriceImpactUtils.ProtectionCloseFactorUpdated(
                _pairIndices[i],
                _protectionCloseFactors[i]
            );
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setProtectionCloseFactorBlocks(
        uint16[] calldata _pairIndices,
        uint32[] calldata _protectionCloseFactorBlocks
    ) internal {
        if (
            _pairIndices.length == 0 ||
            _protectionCloseFactorBlocks.length != _pairIndices.length
        ) revert IGeneralErrors.WrongLength();

        IPriceImpact.PriceImpactStorage storage s = _getStorage();

        for (uint256 i = 0; i < _protectionCloseFactorBlocks.length; ++i) {
            uint32 protectionCloseFactorBlocks = _protectionCloseFactorBlocks[
                i
            ];

            if (
                ChainUtils.convertBlocksToSeconds(
                    uint256(protectionCloseFactorBlocks)
                ) > MAX_PROTECTION_CLOSE_FACTOR_DURATION
            ) revert IGeneralErrors.AboveMax();

            s
                .pairFactors[_pairIndices[i]]
                .protectionCloseFactorBlocks = protectionCloseFactorBlocks;

            emit IPriceImpactUtils.ProtectionCloseFactorBlocksUpdated(
                _pairIndices[i],
                protectionCloseFactorBlocks
            );
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setCumulativeFactors(
        uint16[] calldata _pairIndices,
        uint40[] calldata _cumulativeFactors
    ) internal {
        if (
            _pairIndices.length == 0 ||
            _cumulativeFactors.length != _pairIndices.length
        ) revert IGeneralErrors.WrongLength();

        IPriceImpact.PriceImpactStorage storage s = _getStorage();

        for (uint256 i = 0; i < _cumulativeFactors.length; ++i) {
            if (_cumulativeFactors[i] == 0) revert IGeneralErrors.ZeroValue();

            s
                .pairFactors[_pairIndices[i]]
                .cumulativeFactor = _cumulativeFactors[i];

            emit IPriceImpactUtils.CumulativeFactorUpdated(
                _pairIndices[i],
                _cumulativeFactors[i]
            );
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setExemptOnOpen(
        uint16[] calldata _pairIndices,
        bool[] calldata _exemptOnOpen
    ) internal {
        if (
            _pairIndices.length == 0 ||
            _exemptOnOpen.length != _pairIndices.length
        ) revert IGeneralErrors.WrongLength();

        IPriceImpact.PriceImpactStorage storage s = _getStorage();

        for (uint256 i = 0; i < _exemptOnOpen.length; ++i) {
            s.pairFactors[_pairIndices[i]].exemptOnOpen = _exemptOnOpen[i];

            emit IPriceImpactUtils.ExemptOnOpenUpdated(
                _pairIndices[i],
                _exemptOnOpen[i]
            );
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function setExemptAfterProtectionCloseFactor(
        uint16[] calldata _pairIndices,
        bool[] calldata _exemptAfterProtectionCloseFactor
    ) internal {
        if (
            _pairIndices.length == 0 ||
            _exemptAfterProtectionCloseFactor.length != _pairIndices.length
        ) revert IGeneralErrors.WrongLength();

        IPriceImpact.PriceImpactStorage storage s = _getStorage();

        for (uint256 i = 0; i < _exemptAfterProtectionCloseFactor.length; ++i) {
            s
                .pairFactors[_pairIndices[i]]
                .exemptAfterProtectionCloseFactor = _exemptAfterProtectionCloseFactor[
                i
            ];

            emit IPriceImpactUtils.ExemptAfterProtectionCloseFactorUpdated(
                _pairIndices[i],
                _exemptAfterProtectionCloseFactor[i]
            );
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function addPriceImpactOpenInterest(
        address _trader,
        uint32 _index,
        uint256 _oiDeltaCollateral,
        bool _open,
        bool _isPnlPositive
    ) internal {
        // 1. Prepare variables
        IPriceImpact.OiWindowsSettings storage settings = _getStorage()
            .oiWindowsSettings;
        ITradingStorage.Trade memory trade = _getMultiCollatDiamond().getTrade(
            _trader,
            _index
        );
        ITradingStorage.TradeInfo storage tradeInfo = TradingStorageUtils
            ._getStorage()
            .tradeInfos[_trader][_index];

        uint256 currentWindowId = _getCurrentWindowId(settings);
        uint256 currentCollateralPriceUsd = _getMultiCollatDiamond()
            .getCollateralPriceUsd(trade.collateralIndex);

        uint128 oiDeltaUsd = uint128(
            (TradingCommonUtils.convertCollateralToUsd(
                _oiDeltaCollateral,
                _getMultiCollatDiamond()
                    .getCollateral(trade.collateralIndex)
                    .precisionDelta,
                currentCollateralPriceUsd
            ) *
                (
                    !_open && !_isPnlPositive
                        ? _getStorage().negPnlCumulVolMultiplier
                        : ConstantsUtils.P_10
                )) / ConstantsUtils.P_10
        );

        // 2. Add OI to current window
        IPriceImpact.PairOi storage currentWindow = _getStorage().windows[
            settings.windowsDuration
        ][trade.pairIndex][currentWindowId];
        bool long = (trade.long && _open) || (!trade.long && !_open);

        if (long) {
            currentWindow.oiLongUsd += oiDeltaUsd;
        } else {
            currentWindow.oiShortUsd += oiDeltaUsd;
        }

        // 3. Update trade info
        tradeInfo.lastOiUpdateTs = uint48(block.timestamp);
        tradeInfo.collateralPriceUsd = uint48(currentCollateralPriceUsd);

        emit IPriceImpactUtils.PriceImpactOpenInterestAdded(
            IPriceImpact.OiWindowUpdate(
                _trader,
                _index,
                settings.windowsDuration,
                trade.pairIndex,
                currentWindowId,
                long,
                _open,
                _isPnlPositive,
                oiDeltaUsd
            )
        );
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getPriceImpactOi(
        uint256 _pairIndex,
        bool _long
    ) internal view returns (uint256 activeOi) {
        IPriceImpact.PriceImpactStorage
            storage priceImpactStorage = _getStorage();
        IPriceImpact.OiWindowsSettings storage settings = priceImpactStorage
            .oiWindowsSettings;

        // Return 0 if windowsCount is 0 (no price impact OI)
        if (settings.windowsCount == 0) {
            return 0;
        }

        uint256 currentWindowId = _getCurrentWindowId(settings);
        uint256 earliestWindowId = _getEarliestActiveWindowId(
            currentWindowId,
            settings.windowsCount
        );

        for (uint256 i = earliestWindowId; i <= currentWindowId; ++i) {
            IPriceImpact.PairOi memory _pairOi = priceImpactStorage.windows[
                settings.windowsDuration
            ][_pairIndex][i];
            activeOi += _long ? _pairOi.oiLongUsd : _pairOi.oiShortUsd;
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getTradePriceImpact(
        address _trader,
        uint256 _marketPrice, // 1e10
        uint256 _pairIndex,
        bool _long,
        uint256 _tradeOpenInterestUsd, // 1e18 USD
        bool _isPnlPositive, // only relevant when _open = false
        bool _open,
        uint256 _lastPosIncreaseBlock, // only relevant when _open = false
        ITradingStorage.ContractsVersion _contractsVersion
    )
        internal
        view
        returns (
            uint256 priceImpactP, // 1e10 (%)
            uint256 priceAfterImpact // 1e10
        )
    {
        IPriceImpact.PriceImpactValues memory v;
        v.pairFactors = _getStorage().pairFactors[_pairIndex];
        v.protectionCloseFactorWhitelist = _getStorage()
            .protectionCloseFactorWhitelist[_trader];
        v.userPriceImpact = _getStorage().userPriceImpact[_trader][_pairIndex];

        v.protectionCloseFactorActive =
            _isPnlPositive &&
            !_open &&
            v.pairFactors.protectionCloseFactor != 0 &&
            ChainUtils.getBlockNumber() <=
            _lastPosIncreaseBlock + v.pairFactors.protectionCloseFactorBlocks &&
            !v.protectionCloseFactorWhitelist;

        if (
            (_open && v.pairFactors.exemptOnOpen) ||
            (!_open &&
                !v.protectionCloseFactorActive &&
                v.pairFactors.exemptAfterProtectionCloseFactor)
        ) {
            return (0, _marketPrice);
        }

        v.depth = (_long && _open) || (!_long && !_open)
            ? _getStorage().pairDepths[_pairIndex].onePercentDepthAboveUsd
            : _getStorage().pairDepths[_pairIndex].onePercentDepthBelowUsd; // on close use opposite side depth

        (priceImpactP, priceAfterImpact) = _getTradePriceImpact(
            _marketPrice,
            _long,
            v.depth > 0
                ? getPriceImpactOi(_pairIndex, _open ? _long : !_long)
                : 0, // saves gas if depth is 0
            _tradeOpenInterestUsd,
            v.depth,
            _open,
            ((
                v.protectionCloseFactorActive
                    ? v.pairFactors.protectionCloseFactor
                    : ConstantsUtils.P_10
            ) *
                (
                    v.userPriceImpact.cumulVolPriceImpactMultiplier != 0
                        ? v.userPriceImpact.cumulVolPriceImpactMultiplier
                        : 1e3
                )) / 1e3,
            v.pairFactors.cumulativeFactor != 0
                ? v.pairFactors.cumulativeFactor
                : ConstantsUtils.P_10,
            _contractsVersion
        );
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getPairDepth(
        uint256 _pairIndex
    ) internal view returns (IPriceImpact.PairDepth memory) {
        return _getStorage().pairDepths[_pairIndex];
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getOiWindowsSettings()
        internal
        view
        returns (IPriceImpact.OiWindowsSettings memory)
    {
        return _getStorage().oiWindowsSettings;
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getOiWindow(
        uint48 _windowsDuration,
        uint256 _pairIndex,
        uint256 _windowId
    ) internal view returns (IPriceImpact.PairOi memory) {
        return
            _getStorage().windows[
                _windowsDuration > 0
                    ? _windowsDuration
                    : getOiWindowsSettings().windowsDuration
            ][_pairIndex][_windowId];
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getOiWindows(
        uint48 _windowsDuration,
        uint256 _pairIndex,
        uint256[] calldata _windowIds
    ) internal view returns (IPriceImpact.PairOi[] memory) {
        IPriceImpact.PairOi[] memory _pairOis = new IPriceImpact.PairOi[](
            _windowIds.length
        );

        for (uint256 i; i < _windowIds.length; ++i) {
            _pairOis[i] = getOiWindow(
                _windowsDuration,
                _pairIndex,
                _windowIds[i]
            );
        }

        return _pairOis;
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getPairDepths(
        uint256[] calldata _indices
    ) internal view returns (IPriceImpact.PairDepth[] memory) {
        IPriceImpact.PairDepth[] memory depths = new IPriceImpact.PairDepth[](
            _indices.length
        );

        for (uint256 i = 0; i < _indices.length; ++i) {
            depths[i] = getPairDepth(_indices[i]);
        }

        return depths;
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getPairFactors(
        uint256[] calldata _indices
    ) internal view returns (IPriceImpact.PairFactors[] memory pairFactors) {
        pairFactors = new IPriceImpact.PairFactors[](_indices.length);
        IPriceImpact.PriceImpactStorage storage s = _getStorage();

        for (uint256 i = 0; i < _indices.length; ++i) {
            pairFactors[i] = s.pairFactors[_indices[i]];
        }
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getNegPnlCumulVolMultiplier() internal view returns (uint40) {
        return _getStorage().negPnlCumulVolMultiplier;
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getProtectionCloseFactorWhitelist(
        address _trader
    ) internal view returns (bool) {
        return _getStorage().protectionCloseFactorWhitelist[_trader];
    }

    /**
     * @dev Check IPriceImpactUtils interface for documentation
     */
    function getUserPriceImpact(
        address _trader,
        uint256 _pairIndex
    ) internal view returns (IPriceImpact.UserPriceImpact memory) {
        return _getStorage().userPriceImpact[_trader][_pairIndex];
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_PRICE_IMPACT_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage()
        internal
        pure
        returns (IPriceImpact.PriceImpactStorage storage s)
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
     * @dev Transfers total long / short OI from last '_settings.windowsCount' windows of `_prevPairOiWindows`
     * to current window of `_newPairOiWindows` for `_pairsCount` pairs.
     *
     * Emits a {PriceImpactOiTransferredPairs} event.
     *
     * @param _pairsCount number of pairs
     * @param _prevPairOiWindows previous pair OI windows (previous windowsDuration mapping)
     * @param _newPairOiWindows new pair OI windows (new windowsDuration mapping)
     * @param _settings current OI windows settings
     * @param _newWindowsDuration new windows duration
     */
    function _transferPriceImpactOiForPairs(
        uint256 _pairsCount,
        mapping(uint256 => mapping(uint256 => IPriceImpact.PairOi))
            storage _prevPairOiWindows, // pairIndex => windowId => PairOi
        mapping(uint256 => mapping(uint256 => IPriceImpact.PairOi))
            storage _newPairOiWindows, // pairIndex => windowId => PairOi
        IPriceImpact.OiWindowsSettings memory _settings,
        uint48 _newWindowsDuration
    ) internal {
        uint256 prevCurrentWindowId = _getCurrentWindowId(_settings);
        uint256 prevEarliestWindowId = _getEarliestActiveWindowId(
            prevCurrentWindowId,
            _settings.windowsCount
        );

        uint256 newCurrentWindowId = _getCurrentWindowId(
            IPriceImpact.OiWindowsSettings(
                _settings.startTs,
                _newWindowsDuration,
                _settings.windowsCount
            )
        );

        for (uint256 pairIndex; pairIndex < _pairsCount; ++pairIndex) {
            _transferPriceImpactOiForPair(
                pairIndex,
                prevCurrentWindowId,
                prevEarliestWindowId,
                _prevPairOiWindows[pairIndex],
                _newPairOiWindows[pairIndex][newCurrentWindowId]
            );
        }

        emit IPriceImpactUtils.PriceImpactOiTransferredPairs(
            _pairsCount,
            prevCurrentWindowId,
            prevEarliestWindowId,
            newCurrentWindowId
        );
    }

    /**
     * @dev Transfers total long / short OI from `prevEarliestWindowId` to `prevCurrentWindowId` windows of
     * `_prevPairOiWindows` to `_newPairOiWindow` window.
     *
     * Emits a {PriceImpactOiTransferredPair} event.
     *
     * @param _pairIndex index of the pair
     * @param _prevCurrentWindowId previous current window ID
     * @param _prevEarliestWindowId previous earliest active window ID
     * @param _prevPairOiWindows previous pair OI windows (previous windowsDuration mapping)
     * @param _newPairOiWindow new pair OI window (new windowsDuration mapping)
     */
    function _transferPriceImpactOiForPair(
        uint256 _pairIndex,
        uint256 _prevCurrentWindowId,
        uint256 _prevEarliestWindowId,
        mapping(uint256 => IPriceImpact.PairOi) storage _prevPairOiWindows,
        IPriceImpact.PairOi storage _newPairOiWindow
    ) internal {
        IPriceImpact.PairOi memory totalPairOi;

        // Aggregate sum of total long / short OI for past windows
        for (
            uint256 id = _prevEarliestWindowId;
            id <= _prevCurrentWindowId;
            ++id
        ) {
            IPriceImpact.PairOi memory pairOi = _prevPairOiWindows[id];

            totalPairOi.oiLongUsd += pairOi.oiLongUsd;
            totalPairOi.oiShortUsd += pairOi.oiShortUsd;

            // Clean up previous map once added to the sum
            delete _prevPairOiWindows[id];
        }

        bool longOiTransfer = totalPairOi.oiLongUsd > 0;
        bool shortOiTransfer = totalPairOi.oiShortUsd > 0;

        if (longOiTransfer) {
            _newPairOiWindow.oiLongUsd += totalPairOi.oiLongUsd;
        }

        if (shortOiTransfer) {
            _newPairOiWindow.oiShortUsd += totalPairOi.oiShortUsd;
        }

        // Only emit IPriceImpactUtils.even if there was an actual OI transfer
        if (longOiTransfer || shortOiTransfer) {
            emit IPriceImpactUtils.PriceImpactOiTransferredPair(
                _pairIndex,
                totalPairOi
            );
        }
    }

    /**
     * @dev Returns window id at `_timestamp` given `_settings`.
     * @param _timestamp timestamp
     * @param _settings OI windows settings
     */
    function _getWindowId(
        uint48 _timestamp,
        IPriceImpact.OiWindowsSettings memory _settings
    ) internal pure returns (uint256) {
        return (_timestamp - _settings.startTs) / _settings.windowsDuration;
    }

    /**
     * @dev Returns window id at current timestamp given `_settings`.
     * @param _settings OI windows settings
     */
    function _getCurrentWindowId(
        IPriceImpact.OiWindowsSettings memory _settings
    ) internal view returns (uint256) {
        return _getWindowId(uint48(block.timestamp), _settings);
    }

    /**
     * @dev Returns earliest active window id given `_currentWindowId` and `_windowsCount`.
     * @param _currentWindowId current window id
     * @param _windowsCount active windows count
     */
    function _getEarliestActiveWindowId(
        uint256 _currentWindowId,
        uint48 _windowsCount
    ) internal pure returns (uint256) {
        uint256 windowNegativeDelta = _windowsCount - 1; // -1 because we include current window
        return
            _currentWindowId > windowNegativeDelta
                ? _currentWindowId - windowNegativeDelta
                : 0;
    }

    /**
     * @dev Returns whether '_windowId' can be potentially active id given `_currentWindowId`
     * @param _windowId window id
     * @param _currentWindowId current window id
     */
    function _isWindowPotentiallyActive(
        uint256 _windowId,
        uint256 _currentWindowId
    ) internal pure returns (bool) {
        return _currentWindowId - _windowId < MAX_WINDOWS_COUNT;
    }

    /**
     * @dev Returns trade price impact % and opening price after impact.
     * @param _marketPrice market price (1e10 precision)
     * @param _long true for long, false for short
     * @param _startOpenInterestUsd existing open interest of pair on trade side in USD (1e18 precision)
     * @param _tradeOpenInterestUsd open interest of trade in USD (1e18 precision)
     * @param _onePercentDepthUsd one percent depth of pair in USD on trade side
     * @param _open true for open, false for close
     * @param _priceImpactFactor price impact factor (1e10 precision)
     * @param _cumulativeFactor cumulative factor (1e10 precision)
     * @param _contractsVersion trade contracts version
     */
    function _getTradePriceImpact(
        uint256 _marketPrice,
        bool _long,
        uint256 _startOpenInterestUsd,
        uint256 _tradeOpenInterestUsd,
        uint256 _onePercentDepthUsd,
        bool _open,
        uint256 _priceImpactFactor,
        uint256 _cumulativeFactor,
        ITradingStorage.ContractsVersion _contractsVersion
    )
        internal
        pure
        returns (
            uint256 priceImpactP, // 1e10 (%)
            uint256 priceAfterImpact // 1e10
        )
    {
        // No price impact if 0 depth or if closing trade opened before v9.2
        if (
            _onePercentDepthUsd == 0 ||
            (!_open &&
                _contractsVersion ==
                ITradingStorage.ContractsVersion.BEFORE_V9_2)
        ) {
            return (0, _marketPrice);
        }

        // Half price impact for trades opened after v9.2, full opening price impact for trades opened before v9.2
        priceImpactP =
            (((_startOpenInterestUsd * _cumulativeFactor) /
                ConstantsUtils.P_10 +
                _tradeOpenInterestUsd /
                2) * _priceImpactFactor) /
            _onePercentDepthUsd /
            1e18 /
            (
                _contractsVersion ==
                    ITradingStorage.ContractsVersion.BEFORE_V9_2
                    ? 1
                    : 2
            );

        uint256 priceImpact = (priceImpactP * _marketPrice) /
            ConstantsUtils.P_10 /
            100;

        if (!_open) _long = !_long; // reverse price impact direction on close
        priceAfterImpact = _long
            ? _marketPrice + priceImpact
            : _marketPrice - priceImpact;
    }
}
