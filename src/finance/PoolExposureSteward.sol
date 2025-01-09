// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "solidity-utils/contracts/oz-common/interfaces/IERC20.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {ICollector, CollectorUtils as CU} from "aave-helpers/src/CollectorUtils.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {AaveV2Ethereum, AaveV2EthereumAssets} from "aave-address-book/AaveV2Ethereum.sol";
import {IPoolExposureSteward} from "./interfaces/IPoolExposureSteward.sol";

/**
 * @title PoolExposureSteward
 * @author luigy-lemon  (Karpatkey)
 * @author efecarranza  (Tokenlogic)
 * @notice Manages deposits, withdrawals, and asset migrations between Aave V2 and Aave V3 assets held in the Collector.
 *
 * -- Security Considerations
 *
 * -- Pools
 * The pools managed by the steward are allowListed.
 * As v2 pools are deprecated, the steward only implements withdrawals from v2.
 *
 * -- Permissions
 * The contract implements OwnableWithGuardian.
 * The owner will always be the respective network Short Executor (governance).
 * The guardian role will be given to a Financial Service provider of the DAO.
 *
 * While the permitted Service Provider will have full control over the funds, the allowed actions are limited by the contract itself.
 * All token interactions start and end on the Collector, so no funds ever leave the DAO possession at any point in time.
 */
contract PoolExposureSteward is OwnableWithGuardian, IPoolExposureSteward {
  using CU for ICollector;
  using CU for CU.IOInput;

  /// @inheritdoc IPoolExposureSteward
  ICollector public immutable COLLECTOR;

  /// @inheritdoc IPoolExposureSteward
  mapping(address poolV3 => bool) public poolsV3;
  mapping(address poolV2 => bool) public poolsV2;

  constructor(
    address _owner,
    address _guardian,
    address collector,
    address[] memory _poolsV2,
    address[] memory _poolsV3
  ) {
    _transferOwnership(_owner);
    _updateGuardian(_guardian);

    COLLECTOR = ICollector(collector);

    for (uint256 i; i < _poolsV2.length; i++) {
      _approvePool(_poolsV2[i], false);
    }

    for (uint256 i; i < _poolsV3.length; i++) {
      _approvePool(_poolsV3[i], true);
    }
  }

  /// Steward Actions

  /// @inheritdoc IPoolExposureSteward
  function depositV3(address pool, address reserve, uint256 amount) external onlyOwnerOrGuardian {
    _validateV3Pool(pool);

    CU.IOInput memory depositData = CU.IOInput(pool, reserve, amount);
    CU.depositToV3(COLLECTOR, depositData);
  }

  /// @inheritdoc IPoolExposureSteward
  function withdrawV3(address pool, address reserve, uint256 amount) external onlyOwnerOrGuardian {
    _validateV3Pool(pool);

    CU.IOInput memory withdrawData = CU.IOInput(pool, reserve, amount);
    CU.withdrawFromV3(COLLECTOR, withdrawData, address(COLLECTOR));
  }

  /// @inheritdoc IPoolExposureSteward
  function withdrawV2(address pool, address reserve, uint256 amount) external onlyOwnerOrGuardian {
    _validateV2Pool(pool);

    CU.IOInput memory withdrawData = CU.IOInput(pool, reserve, amount);
    CU.withdrawFromV2(COLLECTOR, withdrawData, address(COLLECTOR));
  }

  /// @inheritdoc IPoolExposureSteward
  function migrateBetweenV3(address fromPool, address toPool, address reserve, uint256 amount)
    external
    onlyOwnerOrGuardian
  {
    _validateV3Pool(fromPool);
    _validateV3Pool(toPool);

    CU.IOInput memory withdrawData = CU.IOInput(fromPool, reserve, amount);
    uint256 withdrawnAmt = CU.withdrawFromV3(COLLECTOR, withdrawData, address(COLLECTOR));

    CU.IOInput memory depositData = CU.IOInput(toPool, reserve, withdrawnAmt);
    CU.depositToV3(COLLECTOR, depositData);
  }

  /// @inheritdoc IPoolExposureSteward
  function migrateV2toV3(address v2Pool, address v3Pool, address reserve, uint256 amount) external onlyOwnerOrGuardian {
    _validateV2Pool(v2Pool);
    _validateV3Pool(v3Pool);

    CU.IOInput memory withdrawData = CU.IOInput(v2Pool, reserve, amount);
    uint256 withdrawnAmt = CU.withdrawFromV2(COLLECTOR, withdrawData, address(COLLECTOR));

    CU.IOInput memory depositData = CU.IOInput(v3Pool, reserve, withdrawnAmt);
    CU.depositToV3(COLLECTOR, depositData);
  }

  /// DAO Actions

  /// @inheritdoc IPoolExposureSteward
  function approvePool(address newPool, bool isVersion3) external onlyOwner {
    _approvePool(newPool, isVersion3);
  }

  /// @inheritdoc IPoolExposureSteward
  function revokePool(address pool, bool isVersion3) external onlyOwner {
    _revokePool(pool, isVersion3);
  }

  /// Logic

  /// @dev Internal function to approve an Aave V3 Pool instance
  function _approvePool(address pool, bool isVersion3) internal {
    if (pool == address(0)) revert InvalidZeroAddress();

    if (isVersion3) {
      poolsV3[pool] = true;
      emit ApprovedV3Pool(pool);
    } else {
      poolsV2[pool] = true;
      emit ApprovedV2Pool(pool);
    }
  }

  /// @dev Internal function to approve an Aave V3 Pool instance
  function _revokePool(address pool, bool isVersion3) internal {
    if (isVersion3) {
      if (poolsV3[pool] == false) revert UnrecognizedPool();
      poolsV3[pool] = false;
      emit RevokedV3Pool(pool);
    } else {
      if (poolsV2[pool] == false) revert UnrecognizedPool();
      poolsV2[pool] = false;
      emit RevokedV2Pool(pool);
    }
  }

  /// @dev Internal function to validate if an Aave V3 Pool instance has been approved
  function _validateV3Pool(address pool) internal view {
    if (poolsV3[pool] == false) revert UnrecognizedPool();
  }

  /// @dev Internal function to validate if an Aave V2 Pool instance has been approved
  function _validateV2Pool(address pool) internal view {
    if (poolsV2[pool] == false) revert UnrecognizedPool();
  }
}
