// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface INegRiskOperator {
    function nrAdapter() external view returns (address);
    function questionIds(bytes32 _requestId) external view returns (bytes32);
}
