// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {MockNegRiskAdapter} from "./MockNegRiskAdapter.sol";

contract MockNegRiskOperator {
    MockNegRiskAdapter public immutable nrAdapter;

    mapping(bytes32 _requestId => bytes32) public questionIds;

    constructor(address _nrAdapter) {
        nrAdapter = MockNegRiskAdapter(_nrAdapter);
    }

    function setQuestionId(bytes32 _requestId, bytes32 _questionId) external {
        questionIds[_requestId] = _questionId;
    }
}
