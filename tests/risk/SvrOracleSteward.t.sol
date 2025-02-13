// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {GovV3Helpers} from "aave-helpers/src/GovV3Helpers.sol";
import {AaveV3Ethereum, AaveV3EthereumAssets} from "aave-address-book/AaveV3Ethereum.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {
  Ownable, OwnableWithGuardian, IWithGuardian
} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";

import {SvrOracleSteward, DeploySvrOracleSteward_Lib} from "../../script/SvrOracleSteward.s.sol";

contract SvrOracleStewardBaseTest is Test {
  SvrOracleSteward internal steward;
  address guardian = address(1);

  function setUp() external {
    vm.createSelectFork(vm.rpcUrl("mainnet"), 21838335);
    steward = DeploySvrOracleSteward_Lib._deployMainnet();
    vm.prank(AaveV3Ethereum.ACL_ADMIN);
    AaveV3Ethereum.ACL_MANAGER.addAssetListingAdmin(address(steward));
  }

  function test_activateSvrOracle() public {
    vm.prank(guardian);
    steward.enableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_disableSvrOracle() external {
    test_activateSvrOracle();
    vm.prank(guardian);
    steward.disableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_ifNoGuardian_activateSvrOracle_shouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianInvalidCaller.selector, address(this)));
    steward.enableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_ifNoGuardian_disableSvrOracle_shouldRevert() external {
    vm.expectRevert(abi.encodeWithSelector(IWithGuardian.OnlyGuardianInvalidCaller.selector, address(this)));
    steward.disableSvrOracle(AaveV3EthereumAssets.cbBTC_UNDERLYING);
  }

  function test_configureOracle() external {
    vm.prank(steward.owner());
    SvrOracleSteward.AssetOracle memory config =
      SvrOracleSteward.AssetOracle({asset: address(9), svrOracle: address(100)});
    steward.configureOracle(config);
  }

  function test_ifNoOwner_configureOracle_shouldRevert() external {
    SvrOracleSteward.AssetOracle memory config =
      SvrOracleSteward.AssetOracle({asset: address(9), svrOracle: address(100)});

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
    steward.configureOracle(config);
  }
}
