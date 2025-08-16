// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../interfaces/libraries/IFeeTiersUtils.sol";
import "../interfaces/IGeneralErrors.sol";

import "../interfaces/types/IFeeTiers.sol";

import "./StorageUtils.sol";

/**
 * @dev GNSFeeTiers facet internal library
 *
 * This is a library to apply fee tiers to trading fees based on a trailing point system.
 */
library FeeTiersUtils {
    uint256 private constant MAX_FEE_TIERS = 8;
    uint32 private constant TRAILING_PERIOD_DAYS = 30;
    uint32 private constant FEE_MULTIPLIER_SCALE = 1e3;
    uint224 private constant POINTS_THRESHOLD_SCALE = 1e18;
    uint256 private constant GROUP_VOLUME_MULTIPLIER_SCALE = 1e3;
    uint224 private constant MAX_CREDITED_POINTS_PER_DAY =
        type(uint224).max / TRAILING_PERIOD_DAYS / 2;

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function initializeFeeTiers(
        uint256[] calldata _groupIndices,
        uint256[] calldata _groupVolumeMultipliers,
        uint256[] calldata _feeTiersIndices,
        IFeeTiers.FeeTier[] calldata _feeTiers
    ) internal {
        setGroupVolumeMultipliers(_groupIndices, _groupVolumeMultipliers);
        setFeeTiers(_feeTiersIndices, _feeTiers);
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function setGroupVolumeMultipliers(
        uint256[] calldata _groupIndices,
        uint256[] calldata _groupVolumeMultipliers
    ) internal {
        if (_groupIndices.length != _groupVolumeMultipliers.length) {
            revert IGeneralErrors.WrongLength();
        }

        mapping(uint256 => uint256)
            storage groupVolumeMultipliers = _getStorage()
                .groupVolumeMultipliers;

        for (uint256 i; i < _groupIndices.length; ++i) {
            groupVolumeMultipliers[_groupIndices[i]] = _groupVolumeMultipliers[
                i
            ];
        }

        emit IFeeTiersUtils.GroupVolumeMultipliersUpdated(
            _groupIndices,
            _groupVolumeMultipliers
        );
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function setFeeTiers(
        uint256[] calldata _feeTiersIndices,
        IFeeTiers.FeeTier[] calldata _feeTiers
    ) internal {
        if (_feeTiersIndices.length != _feeTiers.length) {
            revert IGeneralErrors.WrongLength();
        }

        IFeeTiers.FeeTier[8] storage feeTiersStorage = _getStorage().feeTiers;

        // First do all updates
        for (uint256 i; i < _feeTiersIndices.length; ++i) {
            feeTiersStorage[_feeTiersIndices[i]] = _feeTiers[i];
        }

        // Then check updates are valid
        for (uint256 i; i < _feeTiersIndices.length; ++i) {
            _checkFeeTierUpdateValid(
                _feeTiersIndices[i],
                _feeTiers[i],
                feeTiersStorage
            );
        }

        emit IFeeTiersUtils.FeeTiersUpdated(_feeTiersIndices, _feeTiers);
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function setTradersFeeTiersEnrollment(
        address[] calldata _traders,
        IFeeTiers.TraderEnrollment[] calldata _values
    ) internal {
        if (_traders.length != _values.length) {
            revert IGeneralErrors.WrongLength();
        }

        IFeeTiers.FeeTiersStorage storage s = _getStorage();

        for (uint256 i; i < _traders.length; ++i) {
            (address trader, IFeeTiers.TraderEnrollment memory enrollment) = (
                _traders[i],
                _values[i]
            );

            // Ensure __placeholder remains 0 for future compatibility
            enrollment.__placeholder = 0;

            // Update trader enrollment mapping
            s.traderEnrollments[trader] = enrollment;

            emit IFeeTiersUtils.TraderEnrollmentUpdated(trader, enrollment);
        }
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function addTradersUnclaimedPoints(
        address[] calldata _traders,
        IFeeTiers.CreditType[] calldata _creditTypes,
        uint224[] calldata _points
    ) internal {
        if (
            _traders.length != _creditTypes.length ||
            _traders.length != _points.length
        ) {
            revert IGeneralErrors.WrongLength();
        }

        IFeeTiers.FeeTiersStorage storage s = _getStorage();
        uint32 currentDay = _getCurrentDay();

        for (uint256 i; i < _traders.length; ++i) {
            (
                address trader,
                IFeeTiers.CreditType creditType,
                uint224 points
            ) = (_traders[i], _creditTypes[i], _points[i]);

            // Calculate new total daily points for trader, including unclaimed ones.
            // This ensures that the total daily points for a trader are capped at MAX_CREDITED_POINTS_PER_DAY to prevent trailingPoints
            // from overflowing when points added through trading or other credit events.
            uint224 totalDailyPoints = s
            .traderDailyInfos[trader][currentDay].points +
                s.unclaimedPoints[trader] +
                points;

            // Check total available points are within the safe range
            if (totalDailyPoints > MAX_CREDITED_POINTS_PER_DAY) {
                revert IFeeTiersUtils.PointsOverflow();
            }

            // Add points to unclaimed points storage
            s.unclaimedPoints[trader] += points;

            // If points are to be credited immediately, trigger a points update
            if (creditType == IFeeTiers.CreditType.IMMEDIATE) {
                updateTraderPoints(trader, 0, 0);
            }

            emit IFeeTiersUtils.TraderPointsCredited(
                trader,
                currentDay,
                creditType,
                points
            );
        }
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function updateTraderPoints(
        address _trader,
        uint256 _volumeUsd,
        uint256 _groupIndex
    ) internal {
        IFeeTiers.FeeTiersStorage storage s = _getStorage();

        // Claim any pending points before updating
        _claimUnclaimedPoints(_trader);

        // Scale amount by group multiplier
        uint224 points = uint224(
            (_volumeUsd * s.groupVolumeMultipliers[_groupIndex]) /
                GROUP_VOLUME_MULTIPLIER_SCALE
        );

        mapping(uint32 => IFeeTiers.TraderDailyInfo) storage traderDailyInfo = s
            .traderDailyInfos[_trader];
        uint32 currentDay = _getCurrentDay();
        IFeeTiers.TraderDailyInfo
            storage traderCurrentDayInfo = traderDailyInfo[currentDay];

        // Increase points for current day
        if (points > 0) {
            traderCurrentDayInfo.points += points;
            emit IFeeTiersUtils.TraderDailyPointsIncreased(
                _trader,
                currentDay,
                points
            );
        }

        IFeeTiers.TraderInfo storage traderInfo = s.traderInfos[_trader];

        // Return early if first update ever for trader since trailing points would be 0 anyway
        if (traderInfo.lastDayUpdated == 0) {
            traderInfo.lastDayUpdated = currentDay;
            emit IFeeTiersUtils.TraderInfoFirstUpdate(_trader, currentDay);

            return;
        }

        // Update trailing points & re-calculate cached fee tier.
        // Only run if at least 1 day elapsed since last update
        if (currentDay > traderInfo.lastDayUpdated) {
            // Trailing points = sum of all daily points accumulated for last TRAILING_PERIOD_DAYS.
            // It determines which fee tier to apply (pointsThreshold)
            uint224 curTrailingPoints;

            // Calculate trailing points if less than or exactly TRAILING_PERIOD_DAYS have elapsed since update.
            // Otherwise, trailing points is 0 anyway.
            uint32 earliestActiveDay = currentDay - TRAILING_PERIOD_DAYS;

            if (traderInfo.lastDayUpdated >= earliestActiveDay) {
                // Load current trailing points and add last day updated points since they are now finalized
                curTrailingPoints =
                    traderInfo.trailingPoints +
                    traderDailyInfo[traderInfo.lastDayUpdated].points;

                // Expire outdated trailing points
                uint32 earliestOutdatedDay = traderInfo.lastDayUpdated -
                    TRAILING_PERIOD_DAYS;
                uint32 lastOutdatedDay = earliestActiveDay - 1;

                uint224 expiredTrailingPoints;
                for (
                    uint32 i = earliestOutdatedDay;
                    i <= lastOutdatedDay;
                    ++i
                ) {
                    expiredTrailingPoints += traderDailyInfo[i].points;
                }

                curTrailingPoints -= expiredTrailingPoints;

                emit IFeeTiersUtils.TraderTrailingPointsExpired(
                    _trader,
                    earliestOutdatedDay,
                    lastOutdatedDay,
                    expiredTrailingPoints
                );
            }

            // Store last updated day and new trailing points
            traderInfo.lastDayUpdated = currentDay;
            traderInfo.trailingPoints = curTrailingPoints;

            emit IFeeTiersUtils.TraderInfoUpdated(_trader, traderInfo);

            // Re-calculate current fee tier for trader
            uint32 newFeeMultiplier = FEE_MULTIPLIER_SCALE; // use 1 by default (if no fee tier corresponds)

            for (uint256 i = getFeeTiersCount(); i > 0; --i) {
                IFeeTiers.FeeTier memory feeTier = s.feeTiers[i - 1];

                if (
                    curTrailingPoints >=
                    uint224(feeTier.pointsThreshold) * POINTS_THRESHOLD_SCALE
                ) {
                    newFeeMultiplier = feeTier.feeMultiplier;
                    break;
                }
            }

            // Update trader cached fee multiplier
            traderCurrentDayInfo.feeMultiplierCache = newFeeMultiplier;
            emit IFeeTiersUtils.TraderFeeMultiplierCached(
                _trader,
                currentDay,
                newFeeMultiplier
            );
        }
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function calculateFeeAmount(
        address _trader,
        uint256 _normalFeeAmountCollateral
    ) internal view returns (uint256) {
        IFeeTiers.FeeTiersStorage storage s = _getStorage();
        IFeeTiers.TraderEnrollment storage enrollment = s.traderEnrollments[
            _trader
        ];
        uint32 feeMultiplier = s
        .traderDailyInfos[_trader][_getCurrentDay()].feeMultiplierCache;

        return
            // If  fee multiplier is 0 or trader is excluded, return normal fee amount, otherwise apply multiplier
            feeMultiplier == 0 ||
                enrollment.status == IFeeTiers.TraderEnrollmentStatus.EXCLUDED
                ? _normalFeeAmountCollateral
                : (uint256(feeMultiplier) * _normalFeeAmountCollateral) /
                    uint256(FEE_MULTIPLIER_SCALE);
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function getFeeTiersCount() internal view returns (uint256) {
        IFeeTiers.FeeTier[8] storage _feeTiers = _getStorage().feeTiers;

        for (uint256 i = MAX_FEE_TIERS; i > 0; --i) {
            if (_feeTiers[i - 1].feeMultiplier > 0) {
                return i;
            }
        }

        return 0;
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function getFeeTier(
        uint256 _feeTierIndex
    ) internal view returns (IFeeTiers.FeeTier memory) {
        return _getStorage().feeTiers[_feeTierIndex];
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function getGroupVolumeMultiplier(
        uint256 _groupIndex
    ) internal view returns (uint256) {
        return _getStorage().groupVolumeMultipliers[_groupIndex];
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function getFeeTiersTraderInfo(
        address _trader
    ) internal view returns (IFeeTiers.TraderInfo memory) {
        return _getStorage().traderInfos[_trader];
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function getTraderFeeTiersEnrollment(
        address _trader
    ) internal view returns (IFeeTiers.TraderEnrollment memory) {
        return _getStorage().traderEnrollments[_trader];
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function getTraderUnclaimedPoints(
        address _trader
    ) internal view returns (uint224) {
        return _getStorage().unclaimedPoints[_trader];
    }

    /**
     * @dev Check IFeeTiersUtils interface for documentation
     */
    function getFeeTiersTraderDailyInfo(
        address _trader,
        uint32 _day
    ) internal view returns (IFeeTiers.TraderDailyInfo memory) {
        return _getStorage().traderDailyInfos[_trader][_day];
    }

    /**
     * @dev Returns storage slot to use when fetching storage relevant to library
     */
    function _getSlot() internal pure returns (uint256) {
        return StorageUtils.GLOBAL_FEE_TIERS_SLOT;
    }

    /**
     * @dev Returns storage pointer for storage struct in diamond contract, at defined slot
     */
    function _getStorage()
        internal
        pure
        returns (IFeeTiers.FeeTiersStorage storage s)
    {
        uint256 storageSlot = _getSlot();
        assembly {
            s.slot := storageSlot
        }
    }

    /**
     * @dev Checks validity of a single fee tier update (feeMultiplier: descending, pointsThreshold: ascending, no gap)
     * @param _index index of the fee tier that was updated
     * @param _feeTier fee tier new value
     * @param _feeTiers all fee tiers
     */
    function _checkFeeTierUpdateValid(
        uint256 _index,
        IFeeTiers.FeeTier calldata _feeTier,
        IFeeTiers.FeeTier[8] storage _feeTiers
    ) internal view {
        bool isDisabled = _feeTier.feeMultiplier == 0 &&
            _feeTier.pointsThreshold == 0;

        // Either both feeMultiplier and pointsThreshold are 0 or none
        // And make sure feeMultiplier < 1 && feeMultiplier >= 0.5 to cap discount to 50%
        if (
            !isDisabled &&
            (_feeTier.feeMultiplier >= FEE_MULTIPLIER_SCALE ||
                _feeTier.feeMultiplier < FEE_MULTIPLIER_SCALE / 2 ||
                _feeTier.pointsThreshold == 0)
        ) {
            revert IFeeTiersUtils.WrongFeeTier();
        }

        bool hasNextValue = _index < MAX_FEE_TIERS - 1;

        // If disabled, only need to check the next fee tier is disabled as well to create no gaps in active tiers
        if (isDisabled) {
            if (hasNextValue && _feeTiers[_index + 1].feeMultiplier > 0) {
                revert IGeneralErrors.WrongOrder();
            }
        } else {
            // Check next value order
            if (hasNextValue) {
                IFeeTiers.FeeTier memory feeTier = _feeTiers[_index + 1];
                if (
                    feeTier.feeMultiplier != 0 &&
                    (feeTier.feeMultiplier >= _feeTier.feeMultiplier ||
                        feeTier.pointsThreshold <= _feeTier.pointsThreshold)
                ) {
                    revert IGeneralErrors.WrongOrder();
                }
            }

            // Check previous value order
            if (_index > 0) {
                IFeeTiers.FeeTier memory feeTier = _feeTiers[_index - 1];
                if (
                    feeTier.feeMultiplier <= _feeTier.feeMultiplier ||
                    feeTier.pointsThreshold >= _feeTier.pointsThreshold
                ) {
                    revert IGeneralErrors.WrongOrder();
                }
            }
        }
    }

    /**
     * @dev Get current day (index of mapping traderDailyInfo)
     */
    function _getCurrentDay() internal view returns (uint32) {
        return uint32(block.timestamp / 1 days);
    }

    /**
     * @dev Claims unclaimed points for a trader and adds them to the daily points for the current day.
     * @dev In the event that it's the first points update for the trader, backdates points to yesterday so the tier discount becomes immediate.
     * @param _trader trader address
     */
    function _claimUnclaimedPoints(address _trader) internal {
        IFeeTiers.FeeTiersStorage storage s = _getStorage();

        // Load unclaimed points for trader
        uint224 unclaimedPoints = s.unclaimedPoints[_trader];

        // Return early if no unclaimed points
        if (unclaimedPoints == 0) {
            return;
        }

        IFeeTiers.TraderInfo storage traderInfo = s.traderInfos[_trader];
        uint32 currentDay = _getCurrentDay();

        // Reset unclaimed points storage for trader
        s.unclaimedPoints[_trader] = 0;

        // If it's the first points update we can safely backdate points to yesterday so the tier discount becomes immediate
        if (traderInfo.lastDayUpdated == 0) {
            uint32 yesterday = currentDay - 1;

            // Set trader's last day updated to yesterday (backdate)
            traderInfo.lastDayUpdated = yesterday;
            // Add unclaimed points to yesterday's points
            s.traderDailyInfos[_trader][yesterday].points = unclaimedPoints;

            emit IFeeTiersUtils.TraderInfoFirstUpdate(_trader, yesterday);
        } else {
            // Add unclaimed points to `currentDay`'s points
            s.traderDailyInfos[_trader][currentDay].points += unclaimedPoints;
        }

        emit IFeeTiersUtils.TraderUnclaimedPointsClaimed(
            _trader,
            currentDay,
            unclaimedPoints
        );
    }
}
