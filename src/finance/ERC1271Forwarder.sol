// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import {IComposableCow} from "src/finance/interfaces/IComposableCow.sol";
import {GPv2Order} from "src/finance/libraries/GPv2Order.sol";

/**
 * @title ERC1271 Forwarder - An abstract contract that implements ERC1271 forwarding to ComposableCoW
 * @author mfw78 <mfw78@rndlabs.xyz>
 * @dev Designed to be extended from by a contract that wants to use ComposableCoW
 */
abstract contract ERC1271Forwarder {
    IComposableCow public immutable composableCow;

    constructor(address _composableCow) {
        composableCow = IComposableCow(_composableCow);
    }

    // When the pre-image doesn't match the hash, revert with this error.
    error InvalidHash();

    /**
     * Re-arrange the request into something that ComposableCoW can understand
     * @param _hash GPv2Order.Data digest
     * @param signature The abi.encoded tuple of (GPv2Order.Data, ComposableCoW.PayloadStruct)
     */
    function isValidSignature(
        bytes32 _hash,
        bytes memory signature
    ) public view returns (bytes4) {
        (
            GPv2Order.Data memory order,
            IComposableCow.PayloadStruct memory payload
        ) = abi.decode(
                signature,
                (GPv2Order.Data, IComposableCow.PayloadStruct)
            );
        bytes32 domainSeparator = composableCow.domainSeparator();
        if (!(GPv2Order.hash(order, domainSeparator) == _hash)) {
            revert InvalidHash();
        }

        return
            composableCow.isValidSafeSignature(
                payable(address(this)), // owner
                msg.sender, // sender
                _hash, // GPv2Order digest
                domainSeparator, // GPv2Settlement domain separator
                bytes32(0), // typeHash (not used by ComposableCoW)
                abi.encode(order), // GPv2Order
                abi.encode(payload) // ComposableCoW.PayloadStruct
            );
    }
}
