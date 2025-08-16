// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "../abstract/GNSAddressStore.sol";

import "../../interfaces/libraries/IPairsStorageUtils.sol";

import "../../libraries/PairsStorageUtils.sol";

/**
 * @dev Facet #1: Pairs storage
 */
contract GNSPairsStorage is GNSAddressStore, IPairsStorageUtils {
    // Initialization

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IPairsStorageUtils
    function initializeGroupLiquidationParams(
        IPairsStorage.GroupLiquidationParams[] memory _groupLiquidationParams
    ) external reinitializer(14) {
        PairsStorageUtils.initializeGroupLiquidationParams(
            _groupLiquidationParams
        );
    }

    /// @inheritdoc IPairsStorageUtils
    function initializeNewFees(
        IPairsStorage.GlobalTradeFeeParams memory _tradeFeeParams
    ) external reinitializer(16) {
        PairsStorageUtils.initializeNewFees(_tradeFeeParams);
    }

    /// @inheritdoc IPairsStorageUtils
    function initializeReferralFeeChange() external reinitializer(21) {
        PairsStorageUtils.initializeReferralFeeChange();
    }

    // Management Setters

    /// @inheritdoc IPairsStorageUtils
    function addPairs(Pair[] calldata _pairs) external onlyRole(Role.GOV) {
        PairsStorageUtils.addPairs(_pairs);
    }

    /// @inheritdoc IPairsStorageUtils
    function updatePairs(
        uint256[] calldata _pairIndices,
        Pair[] calldata _pairs
    ) external onlyRoles(Role.GOV_TIMELOCK, Role.GOV_EMERGENCY) {
        PairsStorageUtils.updatePairs(_pairIndices, _pairs);
    }

    /// @inheritdoc IPairsStorageUtils
    function addGroups(Group[] calldata _groups) external onlyRole(Role.GOV) {
        PairsStorageUtils.addGroups(_groups);
    }

    /// @inheritdoc IPairsStorageUtils
    function updateGroups(
        uint256[] calldata _ids,
        Group[] calldata _groups
    ) external onlyRole(Role.GOV) {
        PairsStorageUtils.updateGroups(_ids, _groups);
    }

    /// @inheritdoc IPairsStorageUtils
    function addFees(FeeGroup[] calldata _fees) external onlyRole(Role.GOV) {
        PairsStorageUtils.addFees(_fees);
    }

    /// @inheritdoc IPairsStorageUtils
    function updateFees(
        uint256[] calldata _ids,
        FeeGroup[] calldata _fees
    ) external onlyRoles(Role.GOV_TIMELOCK, Role.GOV_EMERGENCY) {
        PairsStorageUtils.updateFees(_ids, _fees);
    }

    /// @inheritdoc IPairsStorageUtils
    function setGroupLiquidationParams(
        uint256 _groupIndex,
        IPairsStorage.GroupLiquidationParams memory _params
    ) external onlyRoles(Role.GOV_TIMELOCK, Role.GOV_EMERGENCY) {
        PairsStorageUtils.setGroupLiquidationParams(_groupIndex, _params);
    }

    /// @inheritdoc IPairsStorageUtils
    function setGlobalTradeFeeParams(
        IPairsStorage.GlobalTradeFeeParams memory _feeParams
    ) external onlyRole(Role.GOV) {
        PairsStorageUtils.setGlobalTradeFeeParams(_feeParams);
    }

    /// @inheritdoc IPairsStorageUtils
    function setPairCustomMaxLeverages(
        uint256[] calldata _indices,
        uint256[] calldata _values
    ) external onlyRole(Role.MANAGER) {
        PairsStorageUtils.setPairCustomMaxLeverages(_indices, _values);
    }

    // Getters

    /// @inheritdoc IPairsStorageUtils
    function pairJob(
        uint256 _pairIndex
    ) external view returns (string memory, string memory) {
        return PairsStorageUtils.pairJob(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function isPairListed(
        string calldata _from,
        string calldata _to
    ) external view returns (bool) {
        return PairsStorageUtils.isPairListed(_from, _to);
    }

    /// @inheritdoc IPairsStorageUtils
    function isPairIndexListed(
        uint256 _pairIndex
    ) external view returns (bool) {
        return PairsStorageUtils.isPairIndexListed(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairs(uint256 _index) external view returns (Pair memory) {
        return PairsStorageUtils.pairs(_index);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairsCount() external view returns (uint256) {
        return PairsStorageUtils.pairsCount();
    }

    /// @inheritdoc IPairsStorageUtils
    function pairSpreadP(
        address _trader,
        uint256 _pairIndex
    ) external view returns (uint256) {
        return PairsStorageUtils.pairSpreadP(_trader, _pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairSpreadPArray(
        address[] calldata _trader,
        uint256[] calldata _pairIndex
    ) external view returns (uint256[] memory) {
        return PairsStorageUtils.pairSpreadPArray(_trader, _pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairMinLeverage(
        uint256 _pairIndex
    ) external view returns (uint256) {
        return PairsStorageUtils.pairMinLeverage(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairTotalPositionSizeFeeP(
        uint256 _pairIndex
    ) external view returns (uint256) {
        return PairsStorageUtils.pairTotalPositionSizeFeeP(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairTotalLiqCollateralFeeP(
        uint256 _pairIndex
    ) external view returns (uint256) {
        return PairsStorageUtils.pairTotalLiqCollateralFeeP(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairOraclePositionSizeFeeP(
        uint256 _pairIndex
    ) external view returns (uint256) {
        return PairsStorageUtils.pairOraclePositionSizeFeeP(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairMinPositionSizeUsd(
        uint256 _pairIndex
    ) external view returns (uint256) {
        return PairsStorageUtils.pairMinPositionSizeUsd(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function getGlobalTradeFeeParams()
        external
        view
        returns (IPairsStorage.GlobalTradeFeeParams memory)
    {
        return PairsStorageUtils.getGlobalTradeFeeParams();
    }

    /// @inheritdoc IPairsStorageUtils
    function pairMinFeeUsd(uint256 _pairIndex) external view returns (uint256) {
        return PairsStorageUtils.pairMinFeeUsd(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function groups(uint256 _index) external view returns (Group memory) {
        return PairsStorageUtils.groups(_index);
    }

    /// @inheritdoc IPairsStorageUtils
    function groupsCount() external view returns (uint256) {
        return PairsStorageUtils.groupsCount();
    }

    /// @inheritdoc IPairsStorageUtils
    function fees(uint256 _index) external view returns (FeeGroup memory) {
        return PairsStorageUtils.fees(_index);
    }

    /// @inheritdoc IPairsStorageUtils
    function feesCount() external view returns (uint256) {
        return PairsStorageUtils.feesCount();
    }

    /// @inheritdoc IPairsStorageUtils
    function pairMaxLeverage(
        uint256 _pairIndex
    ) external view returns (uint256) {
        return PairsStorageUtils.pairMaxLeverage(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function pairCustomMaxLeverage(
        uint256 _pairIndex
    ) external view returns (uint256) {
        return PairsStorageUtils.pairCustomMaxLeverage(_pairIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function getAllPairsRestrictedMaxLeverage()
        external
        view
        returns (uint256[] memory)
    {
        return PairsStorageUtils.getAllPairsRestrictedMaxLeverage();
    }

    /// @inheritdoc IPairsStorageUtils
    function getGroupLiquidationParams(
        uint256 _groupIndex
    ) external view returns (IPairsStorage.GroupLiquidationParams memory) {
        return PairsStorageUtils.getGroupLiquidationParams(_groupIndex);
    }

    /// @inheritdoc IPairsStorageUtils
    function getPairLiquidationParams(
        uint256 _pairIndex
    ) external view returns (IPairsStorage.GroupLiquidationParams memory) {
        return PairsStorageUtils.getPairLiquidationParams(_pairIndex);
    }
}
