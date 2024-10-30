// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BlastNativeYield} from "./BlastNativeYield.sol";
import {PredictDotLoan} from "./PredictDotLoan.sol";

/**
 * @title  BlastPredictDotLoan
 * @notice BlastPredictDotLoan matches lenders and borrowers
 *         of conditional tokens traded on predict.fun's CTF exchange on Blast.
 * @author predict.fun protocol team
 */
contract BlastPredictDotLoan is BlastNativeYield, PredictDotLoan {
    /**
     * @param _protocolFeeRecipient Protocol fee recipient
     * @param _ctfExchange predict.fun CTF exchange
     * @param _negRiskCtfExchange predict.fun neg risk CTF exchange
     * @param _umaCtfAdapter Binary outcome UMA CTF adapter
     * @param _negRiskUmaCtfAdapter Neg risk UMA CTF adapter
     * @param _negRiskOperator Neg risk operator
     * @param _addressFinder Address finder
     * @param _owner Contract owner
     */
    constructor(
        address _protocolFeeRecipient,
        address _ctfExchange,
        address _negRiskCtfExchange,
        address _umaCtfAdapter,
        address _negRiskUmaCtfAdapter,
        address _negRiskOperator,
        address _addressFinder,
        address _owner
    )
        BlastNativeYield(_addressFinder)
        PredictDotLoan(
            _owner,
            _protocolFeeRecipient,
            _ctfExchange,
            _negRiskCtfExchange,
            _umaCtfAdapter,
            _negRiskUmaCtfAdapter,
            _negRiskOperator
        )
    {}
}
