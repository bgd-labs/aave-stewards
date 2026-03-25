// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ArbSysMock
/// @notice Mocked version of the Arbitrum system contract (precompile at 0x64)
contract ArbSysMock {
    uint256 ticketId;
    address public lastWithdrawDestination;

    function sendTxToL1(
        address _l1Target,
        bytes memory _data
    ) external payable returns (uint256) {
        (bool success, ) = _l1Target.call(_data);
        require(success, "ArbSys: sendTxToL1 failed");
        return ++ticketId;
    }

    function withdrawEth(address destination) external payable returns (uint256) {
        lastWithdrawDestination = destination;
        return ++ticketId;
    }
}
