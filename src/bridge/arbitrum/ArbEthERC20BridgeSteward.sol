// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AaveV3ArbitrumAssets} from "aave-address-book/AaveV3Arbitrum.sol";
import {AaveV3Ethereum} from "aave-address-book/AaveV3Ethereum.sol";
import {ICollector} from "aave-v3-origin/contracts/treasury/ICollector.sol";
import {OwnableWithGuardian} from "solidity-utils/contracts/access-control/OwnableWithGuardian.sol";
import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {RescuableBase, IRescuableBase} from "solidity-utils/contracts/utils/RescuableBase.sol";
import {ChainIds} from "solidity-utils/contracts/utils/ChainHelpers.sol";
import {IWETH} from "aave-v3-origin/contracts/helpers/interfaces/IWETH.sol";

import {IArbEthERC20BridgeSteward} from "./interfaces/IArbEthERC20BridgeSteward.sol";
import {IL2Gateway} from "./interfaces/IL2Gateway.sol";
import {IArbSys} from "./interfaces/IArbSys.sol";

/**
 * @title ArbEthERC20BridgeSteward
 * @author JoFa (Tokenlogic)
 * @notice Bridges funds held in Arbitrum's Collector to Mainnet's Collector.
 *
 * The contract inherits from `Multicall`. Using the `multicall` function from this contract
 * multiple operations can be bundled into a single transaction.
 *
 * -- Security Considerations
 *
 * Not all ERC20 tokens on Arbitrum are compatible with the standard gateway. Governance must
 * only allowlist tokens that can be bridged via their respective L2 gateways. Each token
 * requires the correct gateway address to be specified. Tokens that rely on custom bridges
 * or external protocols must NOT be added to the token mapping:
 *
 * - Native USDC: Bridged via Circle's CCTP, not through the standard gateway.
 * - wstETH: Uses a custom bridge maintained by Lido.
 *
 * -- Permissions
 * The contract implements OwnableWithGuardian.
 * The owner will always be the respective network Level 1 Executor (governance).
 * The guardian role will be given to a Financial Service provider of the DAO (AFC).
 *
 * While the permitted Service Provider will have full operational control within the
 * governance-defined token allowlist, the allowed actions are limited by the contract itself.
 * All token interactions start and end on the Collector, so no funds ever leave the DAO's
 * possession at any point in time.
 */
contract ArbEthERC20BridgeSteward is
    IArbEthERC20BridgeSteward,
    OwnableWithGuardian,
    RescuableBase,
    Multicall
{
    using SafeERC20 for IERC20;

    /// @inheritdoc IArbEthERC20BridgeSteward
    address public constant ARB_SYS =
        0x0000000000000000000000000000000000000064;

    /// @inheritdoc IArbEthERC20BridgeSteward
    address public immutable COLLECTOR;

    /// @inheritdoc IArbEthERC20BridgeSteward
    address public constant MAINNET_COLLECTOR =
        address(AaveV3Ethereum.COLLECTOR);

    /// @inheritdoc IArbEthERC20BridgeSteward
    mapping(address l2Token => TokenConfig) public tokenConfigs;

    uint256 private _nonce;

    /// @param initialOwner The owner of the contract upon deployment
    /// @param initialGuardian The guardian of the contract upon deployment
    /// @param collector The address of the Aave Collector on the deployed chain
    constructor(
        address initialOwner,
        address initialGuardian,
        address collector
    ) OwnableWithGuardian(initialOwner, initialGuardian) {
        if (initialGuardian == address(0)) revert InvalidZeroAddress();
        if (collector == address(0)) revert InvalidZeroAddress();
        COLLECTOR = collector;
    }

    /// @dev Required to receive ETH from WETH.withdraw() during bridgeNative
    receive() external payable {}

    /// @inheritdoc IArbEthERC20BridgeSteward
    function bridge(
        address token,
        uint256 amount
    ) external onlyOwnerOrGuardian {
        if (block.chainid != ChainIds.ARBITRUM) revert InvalidChain();
        if (amount == 0) revert InvalidZeroAmount();

        TokenConfig memory config = tokenConfigs[token];
        if (config.l1Token == address(0)) revert TokenNotAllowed();

        ICollector(COLLECTOR).transfer(IERC20(token), address(this), amount);

        IERC20(token).forceApprove(config.gateway, amount);
        IL2Gateway(config.gateway).outboundTransfer(
            config.l1Token,
            MAINNET_COLLECTOR,
            amount,
            ""
        );

        emit Bridge(token, config.l1Token, amount, MAINNET_COLLECTOR, _nonce++);
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function bridgeNative(uint256 amount) external onlyOwnerOrGuardian {
        if (block.chainid != ChainIds.ARBITRUM) revert InvalidChain();
        if (amount == 0) revert InvalidZeroAmount();
        if (
            tokenConfigs[AaveV3ArbitrumAssets.WETH_UNDERLYING].l1Token ==
            address(0)
        ) revert TokenNotAllowed();
        // Note: the `gateway` field in tokenConfigs[WETH] is not used here.
        // Native ETH withdrawals on Arbitrum must go through ArbSys.withdrawEth,
        // not the ERC20 gateway.

        ICollector(COLLECTOR).transfer(
            IERC20(AaveV3ArbitrumAssets.WETH_UNDERLYING),
            address(this),
            amount
        );
        IWETH(AaveV3ArbitrumAssets.WETH_UNDERLYING).withdraw(amount);

        IArbSys(ARB_SYS).withdrawEth{value: amount}(MAINNET_COLLECTOR);

        emit BridgeNative(amount, MAINNET_COLLECTOR, _nonce++);
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function rescueToken(address token) external onlyOwnerOrGuardian {
        _emergencyTokenTransfer(token, COLLECTOR, type(uint256).max);
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function rescueEth() external onlyOwnerOrGuardian {
        _emergencyEtherTransfer(COLLECTOR, address(this).balance);
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function setTokenMapping(
        address l2Token,
        address l1Token,
        address gateway
    ) external onlyOwner {
        if (block.chainid != ChainIds.ARBITRUM) revert InvalidChain();
        if (l2Token == address(0)) revert InvalidZeroAddress();
        if (l1Token == address(0)) revert InvalidZeroAddress();
        if (gateway == address(0)) revert InvalidZeroAddress();

        tokenConfigs[l2Token] = TokenConfig(l1Token, gateway);
        emit TokenMappingUpdated(l2Token, l1Token, gateway);
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function removeTokenMapping(address l2Token) external onlyOwner {
        if (block.chainid != ChainIds.ARBITRUM) revert InvalidChain();
        if (l2Token == address(0)) revert InvalidZeroAddress();

        delete tokenConfigs[l2Token];
        emit TokenMappingUpdated(l2Token, address(0), address(0));
    }

    /// @inheritdoc IArbEthERC20BridgeSteward
    function nonce() external view returns (uint256) {
        return _nonce;
    }

    /// @inheritdoc IRescuableBase
    function maxRescue(
        address token
    ) public view override(RescuableBase) returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
