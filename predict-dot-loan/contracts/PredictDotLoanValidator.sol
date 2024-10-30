// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPredictDotLoan} from "./interfaces/IPredictDotLoan.sol";
import {ICTFExchange} from "./interfaces/ICTFExchange.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
import {INegRiskAdapter} from "./interfaces/INegRiskAdapter.sol";
import {INegRiskOperator} from "./interfaces/INegRiskOperator.sol";
import {NegRiskIdLib} from "./libraries/NegRiskIdLib.sol";
import {IUmaCtfAdapter} from "./interfaces/IUmaCtfAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {InterestLib} from "./libraries/InterestLib.sol";
import {PredictDotLoan} from "./PredictDotLoan.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "./ValidationCodeConstants.sol";

/**
 * @title PredictDotLoanValidator
 * @notice PredictDotLoanValidator allows users to validate lending/borrowing proposals
 *         It performs checks for:
 *         1. Proposal expiration
 * @author predict.fun protocol team
 */
contract PredictDotLoanValidator {
    /**
     * @notice PredictDotLoan contract
     */
    PredictDotLoan public immutable PREDICT_DOT_LOAN;

    /**
     * @notice Conditional tokens that can be used as collateral
     */
    IConditionalTokens private immutable CTF;

    /**
     * @notice predict.fun The only loan token allowed is the CTF exchange's collateral
     */
    IERC20 private immutable LOAN_TOKEN;

    /**
     * @notice Neg risk adapter
     */
    INegRiskAdapter private immutable NEG_RISK_ADAPTER;

    /**
     * @notice Neg risk operator
     */
    INegRiskOperator public immutable NEG_RISK_OPERATOR;

    /**
     * @notice The protocol charges a fee on each loan. The fee is a percentage of the loan amount.
     */
    uint8 public protocolFeeBasisPoints;

    /**
     * @notice The maximum protocol fee is 2%
     */
    uint256 private constant MAXIMUM_PROTOCOL_FEE_BASIS_POINTS = 200;

    error NotAdmin();
    error ProtocolFeeBasisPointsTooHigh();

    /**
     * @param _predictDotLoanAddress PredictDotLoan contract address
     */
    constructor(address _predictDotLoanAddress, uint8 _protocolFeeBasisPoints) {
        PREDICT_DOT_LOAN = PredictDotLoan(_predictDotLoanAddress);

        ICTFExchange ctfExchange = PREDICT_DOT_LOAN.CTF_EXCHANGE();
        ICTFExchange negRiskCtfExchange = PREDICT_DOT_LOAN.NEG_RISK_CTF_EXCHANGE();

        LOAN_TOKEN = IERC20(ctfExchange.getCollateral());

        NEG_RISK_ADAPTER = INegRiskAdapter(negRiskCtfExchange.getCtf());
        NEG_RISK_OPERATOR = PREDICT_DOT_LOAN.NEG_RISK_OPERATOR();

        CTF = IConditionalTokens(ctfExchange.getCtf());

        protocolFeeBasisPoints = _protocolFeeBasisPoints;
    }

    /**
     * @dev Shared validation logic between loan offers and borrow requests
     *
     * @notice This function verifies the validity of a proposal
     *
     * @param proposal The Proposal struct
     * @param taker The user who wishes to accept a given proposal
     * @param fulfillAmount The loan amount to be fulfilled
     *
     * @return validationCodes Array of validation codes
     */
    function validateProposal(
        IPredictDotLoan.Proposal calldata proposal,
        address taker,
        uint256 fulfillAmount
    ) public view returns (uint256[13] memory validationCodes) {
        bytes32 proposalId = PREDICT_DOT_LOAN.hashProposal(proposal);
        (bytes32 fulfillmentProposalId, , uint256 loanAmount) = PREDICT_DOT_LOAN.getFulfillment(proposal);
        address lender = proposal.proposalType == IPredictDotLoan.ProposalType.LoanOffer ? proposal.from : taker;
        address borrower = proposal.proposalType == IPredictDotLoan.ProposalType.BorrowRequest ? proposal.from : taker;

        validationCodes[0] = _validateExpiration(proposal);
        validationCodes[1] = _validateLenderIsNotBorrower(proposal, taker);
        validationCodes[2] = _validateSignature(proposalId, proposal.from, proposal.signature);
        validationCodes[3] = _validateFulfillAmount(fulfillAmount, loanAmount, proposal.loanAmount);
        validationCodes[4] = _validateSalt(
            fulfillmentProposalId,
            proposalId,
            proposal.from,
            proposal.salt,
            proposal.proposalType
        );
        validationCodes[5] = _validateNonceIsCurrent(proposal.proposalType, proposal.from, proposal.nonce);
        validationCodes[6] = _validateCollateralizationRatio(proposal.collateralAmount, proposal.loanAmount);
        validationCodes[7] = _validateInterestRate(proposal.interestRatePerSecond);
        validationCodes[8] = _validatePositionIsTradeable(proposal);
        validationCodes[9] = _validateQuestionState(proposal.questionType, proposal.questionId);
        validationCodes[10] = _validateMatchingProtocolFeeBasisPoints(proposal.protocolFeeBasisPoints);
        validationCodes[11] = _validateLenderLoanTokenApproval(proposal, lender);
        validationCodes[12] = _validateBorrowerCollateralTokenApproval(borrower);
    }

    /**
     * @notice This function verifies the validity of the borrow request, the loan offer and their ability to be matched against one another.
     *
     * @param borrowRequest The borrow request to be matched
     * @param loanOffer The loan offer to be matched
     *
     * @return validationCodes Array of validation codes
     */
    function validate_matchProposals(
        IPredictDotLoan.Proposal calldata borrowRequest,
        IPredictDotLoan.Proposal calldata loanOffer
    ) public view returns (uint256[12] memory validationCodes) {
        bytes32 borrowRequestId = PREDICT_DOT_LOAN.hashProposal(borrowRequest);
        bytes32 loanOfferId = PREDICT_DOT_LOAN.hashProposal(loanOffer);
        (bytes32 fulfillmentBorrowRequestId, , uint256 borrowRequestLoanAmount) = PREDICT_DOT_LOAN.getFulfillment(
            borrowRequest
        );
        (bytes32 fulfillmentLoanOfferId, , uint256 loanOfferLoanAmount) = PREDICT_DOT_LOAN.getFulfillment(loanOffer);

        validationCodes[0] = _validate_matchProposals_Expiration(borrowRequest, loanOffer);
        validationCodes[1] = _validate_matchProposals_LenderIsNotBorrower(borrowRequest, loanOffer);
        validationCodes[2] = _validate_matchProposals_Signatures(
            borrowRequestId,
            loanOfferId,
            borrowRequest,
            loanOffer
        );
        validationCodes[3] = _validate_matchProposals_FulfillAmount(
            borrowRequestLoanAmount,
            borrowRequest.loanAmount,
            loanOfferLoanAmount,
            loanOffer.loanAmount
        );
        validationCodes[4] = _validate_matchProposals_Salts(
            fulfillmentBorrowRequestId,
            fulfillmentLoanOfferId,
            borrowRequestId,
            loanOfferId,
            borrowRequest.from,
            loanOffer.from,
            borrowRequest.salt,
            loanOffer.salt
        );
        validationCodes[5] = _validate_matchProposals_NoncesAreCurrent(
            borrowRequest.from,
            loanOffer.from,
            borrowRequest.nonce,
            loanOffer.nonce
        );
        validationCodes[6] = _validate_matchProposals_CollateralizationRatios(
            borrowRequest.collateralAmount,
            loanOffer.collateralAmount,
            borrowRequest.loanAmount,
            loanOffer.loanAmount
        );
        validationCodes[7] = _validate_matchProposals_InterestRates(
            borrowRequest.interestRatePerSecond,
            loanOffer.interestRatePerSecond
        );
        validationCodes[8] = _validate_matchProposals_PositionsAreTradeable(borrowRequest, loanOffer);
        validationCodes[9] = _validate_matchProposals_QuestionStates(
            borrowRequest.questionType,
            loanOffer.questionType,
            borrowRequest.questionId,
            loanOffer.questionId
        );
        validationCodes[10] = _validate_matchProposals_CorrectProposalRequestTypes(borrowRequest, loanOffer);
        validationCodes[11] = _validate_matchProposals_ProtocolFeeBasisPoints(
            borrowRequest.protocolFeeBasisPoints,
            loanOffer.protocolFeeBasisPoints
        );
    }

    /**
     * @notice This function checks if the borrow request and/or loan offer has expired
     *
     * @param borrowRequest The borrow request to be matched
     * @param loanOffer The loan offer to be matched
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_Expiration(
        IPredictDotLoan.Proposal calldata borrowRequest,
        IPredictDotLoan.Proposal calldata loanOffer
    ) private view returns (uint256 validationCode) {
        if (block.timestamp > borrowRequest.validUntil && block.timestamp > loanOffer.validUntil) {
            return BORROW_REQUEST_AND_LOAN_OFFER_EXPIRED;
        } else if (block.timestamp > borrowRequest.validUntil) {
            return BORROW_REQUEST_EXPIRED;
        } else if (block.timestamp > loanOffer.validUntil) {
            return LOAN_OFFER_EXPIRED;
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the lender is the borrower for a proposal match
     *
     * @param borrowRequest The borrow request to be matched
     * @param loanOffer The loan offer to be matched
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_LenderIsNotBorrower(
        IPredictDotLoan.Proposal calldata borrowRequest,
        IPredictDotLoan.Proposal calldata loanOffer
    ) private pure returns (uint256 validationCode) {
        if (borrowRequest.from == loanOffer.from) {
            return LENDER_IS_BORROWER;
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the signatures are valid for the borrow request and loan offer that are to be matched
     *
     * @param borrowRequestId The borrow request id
     * @param loanOfferId The loan offer id
     * @param borrowRequest The borrow request to be matched
     * @param loanOffer The loan offer to be matched
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_Signatures(
        bytes32 borrowRequestId,
        bytes32 loanOfferId,
        IPredictDotLoan.Proposal calldata borrowRequest,
        IPredictDotLoan.Proposal calldata loanOffer
    ) private view returns (uint256 validationCode) {
        bool borrowRequestSignatureValidity = SignatureChecker.isValidSignatureNow(
            borrowRequest.from,
            borrowRequestId,
            borrowRequest.signature
        );
        bool loanOfferSignatureValidity = SignatureChecker.isValidSignatureNow(
            loanOffer.from,
            loanOfferId,
            loanOffer.signature
        );

        if (!borrowRequestSignatureValidity && !loanOfferSignatureValidity) {
            return INVALID_BORROW_REQUEST_AND_LOAN_OFFER_SIGNATURE;
        } else if (!borrowRequestSignatureValidity) {
            return INVALID_BORROW_REQUEST_SIGNATURE;
        } else if (!loanOfferSignatureValidity) {
            return INVALID_LOAN_OFFER_SIGNATURE;
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the fulfill amount is valid (not too low or too high) for the borrow request and loan offer that are to be matched
     *
     * @param borrowRequestFulfilledAmount The borrow request's amount fulfilled
     * @param borrowRequestLoanAmount The borrow request's loan amount
     * @param loanOfferFulfilledAmount The loan offer's amount fulfilled
     * @param loanOfferLoanAmount The loan offer's loan amount
     *
     * @return validationCode Validation code
     */

    function _validate_matchProposals_FulfillAmount(
        uint256 borrowRequestFulfilledAmount,
        uint256 borrowRequestLoanAmount,
        uint256 loanOfferFulfilledAmount,
        uint256 loanOfferLoanAmount
    ) private pure returns (uint256 validationCode) {
        uint256 loanOfferAvailableFulfillAmount = loanOfferLoanAmount - loanOfferFulfilledAmount;
        uint256 borrowRequestAvailableFulfillAmount = borrowRequestLoanAmount - borrowRequestFulfilledAmount;
        uint256 fulfillAmount = loanOfferAvailableFulfillAmount > borrowRequestAvailableFulfillAmount
            ? borrowRequestAvailableFulfillAmount
            : loanOfferAvailableFulfillAmount;

        uint256 borrowRequestValidationCode = _validateFulfillAmount(
            fulfillAmount,
            borrowRequestFulfilledAmount,
            borrowRequestLoanAmount
        );
        uint256 loanOfferValidationCode = _validateFulfillAmount(
            fulfillAmount,
            loanOfferFulfilledAmount,
            loanOfferLoanAmount
        );

        if (borrowRequestValidationCode == FULFILL_AMOUNT_TOO_LOW) {
            return BORROW_REQUEST_FULFILL_AMOUNT_TOO_LOW;
        }

        if (loanOfferValidationCode == FULFILL_AMOUNT_TOO_LOW) {
            return LOAN_OFFER_FULFILL_AMOUNT_TOO_LOW;
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the borrow request and loan offer's salts are not cancelled and/or used by another proposal
     *
     * @param fulfillmentBorrowRequestId The fulfillment's borrow request ID, it's 0 if there is no fulfillment
     * @param fulfillmentLoanOfferId The fulfillment's loan offer ID, it's 0 if there is no fulfillment
     * @param borrowRequestId The borrow request ID
     * @param loanOfferId The loan offer ID
     * @param borrower The borrower's address
     * @param lender The lender's address
     * @param borrowerRequestSalt The borrower request's salt
     * @param loanOfferSalt The loan offer's salt
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_Salts(
        bytes32 fulfillmentBorrowRequestId,
        bytes32 fulfillmentLoanOfferId,
        bytes32 borrowRequestId,
        bytes32 loanOfferId,
        address borrower,
        address lender,
        uint256 borrowerRequestSalt,
        uint256 loanOfferSalt
    ) private view returns (uint256 validationCode) {
        (, bool _borrowing) = PREDICT_DOT_LOAN.saltCancellations(borrower, borrowerRequestSalt);
        (bool _lending, ) = PREDICT_DOT_LOAN.saltCancellations(lender, loanOfferSalt);

        if (fulfillmentBorrowRequestId != bytes32(0)) {
            if ((fulfillmentBorrowRequestId != borrowRequestId) && _lending) {
                return BORROW_REQUEST_SALT_ALREADY_USED_AND_LOAN_OFFER_CANCELLED;
            }
        }

        if (fulfillmentLoanOfferId != bytes32(0)) {
            if ((fulfillmentLoanOfferId != loanOfferId) && _borrowing) {
                return LOAN_OFFER_SALT_ALREADY_USED_AND_BORROW_REQUEST_CANCELLED;
            }
        }

        if (_borrowing && _lending) {
            return BORROW_REQUEST_AND_LOAN_OFFER_CANCELLED;
        }

        if (_borrowing) {
            return BORROW_REQUEST_CANCELLED;
        }

        if (_lending) {
            return LOAN_OFFER_CANCELLED;
        }

        if ((fulfillmentBorrowRequestId != bytes32(0)) && (fulfillmentLoanOfferId != bytes32(0))) {
            if ((fulfillmentBorrowRequestId != borrowRequestId) && (fulfillmentLoanOfferId != loanOfferId)) {
                return BORROW_REQUEST_AND_LOAN_OFFER_SALTS_ALREADY_USED;
            }
        }

        if (fulfillmentBorrowRequestId != bytes32(0)) {
            if (fulfillmentBorrowRequestId != borrowRequestId) {
                return BORROW_REQUEST_SALT_ALREADY_USED;
            }
        }

        if (fulfillmentLoanOfferId != bytes32(0)) {
            if (fulfillmentLoanOfferId != loanOfferId) {
                return LOAN_OFFER_SALT_ALREADY_USED;
            }
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the borrow request and loan offer's nonces matches their signer's nonces
     *
     * @param borrower The borrower
     * @param lender The lender
     * @param borrowerNonce The borrower's nonce
     * @param lenderNonce The lender's nonce
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_NoncesAreCurrent(
        address borrower,
        address lender,
        uint256 borrowerNonce,
        uint256 lenderNonce
    ) private view returns (uint256 validationCode) {
        (, uint256 borrowingNonce) = PREDICT_DOT_LOAN.nonces(borrower);
        (uint256 lendingNonce, ) = PREDICT_DOT_LOAN.nonces(lender);

        if ((borrowerNonce != borrowingNonce) && (lenderNonce != lendingNonce)) {
            return BORROW_REQUEST_AND_LOAN_OFFER_NONCES_ARE_NOT_CURRENT;
        }

        if (borrowerNonce != borrowingNonce) {
            return BORROW_REQUEST_NONCE_IS_NOT_CURRENT;
        }

        if (lenderNonce != lendingNonce) {
            return LOAN_OFFER_NONCE_IS_NOT_CURRENT;
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the borrow request and loan offer's collateralization ratios are equal to or above 100%
     *
     * @param borrowRequestCollateralAmount The borrow request's collateral amount
     * @param loanOfferCollateralAmount The loan offer's collateral amount
     * @param borrowRequestLoanAmount The borrow request's loan amount
     * @param loanOfferLoanAmount The loan offer's loan amount
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_CollateralizationRatios(
        uint256 borrowRequestCollateralAmount,
        uint256 loanOfferCollateralAmount,
        uint256 borrowRequestLoanAmount,
        uint256 loanOfferLoanAmount
    ) private pure returns (uint256 validationCode) {
        if (
            (borrowRequestCollateralAmount < borrowRequestLoanAmount) &&
            (loanOfferCollateralAmount < loanOfferLoanAmount)
        ) {
            return BORROW_REQUEST_AND_LOAN_OFFER_COLLATERALIZATION_RATIOS_BELOW_100;
        }

        if (borrowRequestCollateralAmount < borrowRequestLoanAmount) {
            return BORROW_REQUEST_COLLATERALIZATION_RATIO_BELOW_100;
        }

        if (loanOfferCollateralAmount < loanOfferLoanAmount) {
            return LOAN_OFFER_COLLATERALIZATION_RATIO_BELOW_100;
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the borrow request and loan offer's interest rates are above the minimum interest rate
     *         and below the maximum interest rate.
     *
     * @param borrowRequestInterestRatePerSecond The borrow request's interest rate
     * @param loanOfferInterestRatePerSecond The loan offer's interest rate
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_InterestRates(
        uint256 borrowRequestInterestRatePerSecond,
        uint256 loanOfferInterestRatePerSecond
    ) private pure returns (uint256 validationCode) {
        uint256 maximumInterestRate = InterestLib.ONE + InterestLib.TEN_THOUSAND_APY;

        if (
            borrowRequestInterestRatePerSecond > maximumInterestRate &&
            loanOfferInterestRatePerSecond > maximumInterestRate
        ) {
            return BORROW_REQUEST_AND_LOAN_OFFER_INTEREST_RATES_TOO_HIGH;
        }

        if (
            borrowRequestInterestRatePerSecond <= InterestLib.ONE && loanOfferInterestRatePerSecond <= InterestLib.ONE
        ) {
            return BORROW_REQUEST_AND_LOAN_OFFER_INTEREST_RATES_TOO_LOW;
        }

        if (
            borrowRequestInterestRatePerSecond <= InterestLib.ONE &&
            loanOfferInterestRatePerSecond > maximumInterestRate
        ) {
            return BORROW_REQUEST_INTEREST_RATE_TOO_LOW_AND_LOAN_OFFER_INTEREST_RATE_TOO_HIGH;
        }

        if (
            borrowRequestInterestRatePerSecond > maximumInterestRate &&
            loanOfferInterestRatePerSecond <= InterestLib.ONE
        ) {
            return BORROW_REQUEST_INTEREST_RATE_TOO_HIGH_AND_LOAN_OFFER_INTEREST_RATE_TOO_LOW;
        }

        if (borrowRequestInterestRatePerSecond <= InterestLib.ONE) {
            return BORROW_REQUEST_INTEREST_RATE_TOO_LOW;
        }

        if (borrowRequestInterestRatePerSecond > maximumInterestRate) {
            return BORROW_REQUEST_INTEREST_RATE_TOO_HIGH;
        }

        if (loanOfferInterestRatePerSecond <= InterestLib.ONE) {
            return LOAN_OFFER_INTEREST_RATE_TOO_LOW;
        }

        if (loanOfferInterestRatePerSecond > maximumInterestRate) {
            return LOAN_OFFER_INTEREST_RATE_TOO_HIGH;
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the positions are tradeable on the exchange or the neg risk CTF exchange.
     *
     * @param borrowRequest The borrow request
     * @param loanOffer The loan offer
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_PositionsAreTradeable(
        IPredictDotLoan.Proposal calldata borrowRequest,
        IPredictDotLoan.Proposal calldata loanOffer
    ) private view returns (uint256 validationCode) {
        uint256 borrowRequestPositionId = _derivePositionId(borrowRequest);
        uint256 loanOfferPositionId = _derivePositionId(loanOffer);

        ICTFExchange borrowRequestExchange = borrowRequest.questionType == IPredictDotLoan.QuestionType.Binary
            ? PREDICT_DOT_LOAN.CTF_EXCHANGE()
            : PREDICT_DOT_LOAN.NEG_RISK_CTF_EXCHANGE();
        ICTFExchange loanOfferExchange = loanOffer.questionType == IPredictDotLoan.QuestionType.Binary
            ? PREDICT_DOT_LOAN.CTF_EXCHANGE()
            : PREDICT_DOT_LOAN.NEG_RISK_CTF_EXCHANGE();

        (uint256 borrowRequestComplement, ) = borrowRequestExchange.registry(borrowRequestPositionId);
        (uint256 loanOfferComplement, ) = loanOfferExchange.registry(loanOfferPositionId);

        if ((borrowRequestComplement == 0) && (loanOfferComplement == 0)) {
            return BORROW_REQUEST_AND_LOAN_OFFER_POSITIONS_ARE_NOT_TRADEABLE;
        }

        if (borrowRequestComplement == 0) {
            return BORROW_REQUEST_POSITION_IS_NOT_TRADEABLE;
        }

        if (loanOfferComplement == 0) {
            return LOAN_OFFER_POSITION_IS_NOT_TRADEABLE;
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the question prices are available for both the borrow request and loan offer
     *
     * @dev We do not allow positions that are already resolved from being used as collaterals for loans
     *      as it is very likely that the position is worth nothing
     *
     * @param borrowRequestQuestionType The borrow request question type
     * @param loanOfferQuestionType The loan offer question type
     * @param borrowRequestId The borrow request ID
     * @param loanOfferId The loan offer ID
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_QuestionStates(
        IPredictDotLoan.QuestionType borrowRequestQuestionType,
        IPredictDotLoan.QuestionType loanOfferQuestionType,
        bytes32 borrowRequestId,
        bytes32 loanOfferId
    ) private view returns (uint256 validationCode) {
        uint256 borrowRequestValidationCode = _validateQuestionState(borrowRequestQuestionType, borrowRequestId);
        uint256 loanOfferValidationCode = _validateQuestionState(loanOfferQuestionType, loanOfferId);

        if (
            (borrowRequestValidationCode == PROPOSAL_EXPECTED_TO_BE_VALID) &&
            (loanOfferValidationCode == PROPOSAL_EXPECTED_TO_BE_VALID)
        ) {
            validationCode = MATCHING_EXPECTED_TO_BE_VALID;
        }

        if (
            (borrowRequestValidationCode == QUESTION_STATE_ABNORMAL) &&
            (loanOfferValidationCode == PROPOSAL_EXPECTED_TO_BE_VALID)
        ) {
            validationCode = BORROW_REQUEST_QUESTION_STATE_ABNORMAL;
        }

        if (
            (borrowRequestValidationCode == PROPOSAL_EXPECTED_TO_BE_VALID) &&
            (loanOfferValidationCode == QUESTION_STATE_ABNORMAL)
        ) {
            validationCode = LOAN_OFFER_QUESTION_STATE_ABNORMAL;
        }

        if (
            (borrowRequestValidationCode == QUESTION_STATE_ABNORMAL) &&
            (loanOfferValidationCode == QUESTION_STATE_ABNORMAL)
        ) {
            validationCode = BORROW_REQUEST_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL;
        }

        if (
            (borrowRequestValidationCode == QUESTION_RESOLVED) &&
            (loanOfferValidationCode == PROPOSAL_EXPECTED_TO_BE_VALID)
        ) {
            validationCode = BORROW_REQUEST_QUESTION_RESOLVED;
        }

        if (
            (borrowRequestValidationCode == PROPOSAL_EXPECTED_TO_BE_VALID) &&
            (loanOfferValidationCode == QUESTION_RESOLVED)
        ) {
            validationCode = LOAN_OFFER_QUESTION_RESOLVED;
        }

        if ((borrowRequestValidationCode == QUESTION_RESOLVED) && (loanOfferValidationCode == QUESTION_RESOLVED)) {
            validationCode = BORROW_REQUEST_AND_LOAN_OFFER_QUESTIONS_RESOLVED;
        }

        if (
            (borrowRequestValidationCode == MARKET_RESOLVED) &&
            (loanOfferValidationCode == PROPOSAL_EXPECTED_TO_BE_VALID)
        ) {
            validationCode = BORROW_REQUEST_MARKET_RESOLVED;
        }

        if (
            (borrowRequestValidationCode == PROPOSAL_EXPECTED_TO_BE_VALID) &&
            (loanOfferValidationCode == MARKET_RESOLVED)
        ) {
            validationCode = LOAN_OFFER_MARKET_RESOLVED;
        }

        if ((borrowRequestValidationCode == MARKET_RESOLVED) && (loanOfferValidationCode == MARKET_RESOLVED)) {
            validationCode = BORROW_REQUEST_AND_LOAN_OFFER_MARKETS_RESOLVED;
        }

        if (
            (borrowRequestValidationCode == QUESTION_RESOLVED) && (loanOfferValidationCode == QUESTION_STATE_ABNORMAL)
        ) {
            validationCode = BORROW_REQUEST_QUESTION_RESOLVED_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL;
        }

        if (
            (borrowRequestValidationCode == QUESTION_STATE_ABNORMAL) && (loanOfferValidationCode == QUESTION_RESOLVED)
        ) {
            validationCode = BORROW_REQUEST_QUESTION_STATE_ABNORMAL_AND_LOAN_OFFER_QUESTION_RESOLVED;
        }

        if ((borrowRequestValidationCode == QUESTION_RESOLVED) && (loanOfferValidationCode == MARKET_RESOLVED)) {
            validationCode = BORROW_REQUEST_QUESTION_RESOLVED_AND_LOAN_OFFER_MARKET_RESOLVED;
        }

        if ((borrowRequestValidationCode == MARKET_RESOLVED) && (loanOfferValidationCode == QUESTION_RESOLVED)) {
            validationCode = BORROW_REQUEST_MARKET_RESOLVED_AND_LOAN_OFFER_QUESTION_RESOLVED;
        }

        if ((borrowRequestValidationCode == QUESTION_STATE_ABNORMAL) && (loanOfferValidationCode == MARKET_RESOLVED)) {
            validationCode = BORROW_REQUEST_QUESTION_STATE_ABNORMAL_AND_LOAN_OFFER_MARKET_RESOLVED;
        }

        if ((borrowRequestValidationCode == MARKET_RESOLVED) && (loanOfferValidationCode == QUESTION_STATE_ABNORMAL)) {
            validationCode = BORROW_REQUEST_MARKET_RESOLVED_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL;
        }

        return validationCode;
    }

    /**
     * @notice This function checks if the borrow request and loan offer are of the appropriate types
     *
     * @param borrowRequest The borrow request to be matched
     * @param loanOffer The loan offer to be matched
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_CorrectProposalRequestTypes(
        IPredictDotLoan.Proposal calldata borrowRequest,
        IPredictDotLoan.Proposal calldata loanOffer
    ) private pure returns (uint256 validationCode) {
        if (
            (borrowRequest.proposalType != IPredictDotLoan.ProposalType.BorrowRequest) &&
            (loanOffer.proposalType != IPredictDotLoan.ProposalType.LoanOffer)
        ) {
            return INCORRECT_PROPOSAL_TYPES_FOR_BORROW_REQUEST_AND_LOAN_OFFER;
        } else if (borrowRequest.proposalType != IPredictDotLoan.ProposalType.BorrowRequest) {
            return INCORRECT_PROPOSAL_TYPE_FOR_BORROW_REQUEST;
        } else if (loanOffer.proposalType != IPredictDotLoan.ProposalType.LoanOffer) {
            return INCORRECT_PROPOSAL_TYPE_FOR_LOAN_OFFER;
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }

    /*//////////////////////////////////////////////////////////////
                    REGULAR PROPOSAL VALIDATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice This function checks if the proposal has expired
     *
     * @param proposal The Proposal struct
     *
     * @return validationCode Validation code
     */
    function _validateExpiration(
        IPredictDotLoan.Proposal calldata proposal
    ) private view returns (uint256 validationCode) {
        if (block.timestamp > proposal.validUntil) {
            return PROPOSAL_EXPIRED;
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the lender is the borrower
     *
     * @param proposal The Proposal
     * @param taker The user who wishes to accept a given proposal
     *
     * @return validationCode Validation code
     */
    function _validateLenderIsNotBorrower(
        IPredictDotLoan.Proposal calldata proposal,
        address taker
    ) private pure returns (uint256 validationCode) {
        address proposalCreator = proposal.from;
        if (proposalCreator == taker) {
            return LENDER_IS_BORROWER;
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the signature is valid.
     *
     * @param proposalId The Proposal ID
     * @param from The signer
     * @param signature The signature
     *
     * @return validationCode Validation code
     */
    function _validateSignature(
        bytes32 proposalId,
        address from,
        bytes calldata signature
    ) private view returns (uint256 validationCode) {
        if (!SignatureChecker.isValidSignatureNow(from, proposalId, signature)) {
            return INVALID_SIGNATURE;
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the fulfill amount is valid (not too low or too high)
     *
     * @param fulfillAmount The loan amount to be fulfilled
     * @param fulfilledAmount The loan amount fulfilled
     * @param loanAmount The proposal's loan amount
     *
     * @return validationCode Validation code
     */
    function _validateFulfillAmount(
        uint256 fulfillAmount,
        uint256 fulfilledAmount,
        uint256 loanAmount
    ) private pure returns (uint256 validationCode) {
        if (fulfillAmount == 0) {
            return FULFILL_AMOUNT_TOO_LOW;
        }

        if (fulfillAmount != loanAmount - fulfilledAmount) {
            if (fulfillAmount < loanAmount / 10) {
                return FULFILL_AMOUNT_TOO_LOW;
            }
        }

        if (fulfilledAmount + fulfillAmount > loanAmount) {
            return FULFILL_AMOUNT_TOO_HIGH;
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the proposal's salt is not cancelled and not used by another proposal
     *
     * @param fulfillmentProposalId The fulfillment's proposal ID, it's 0 if there is no fulfillment
     * @param proposalId The proposal ID
     * @param user The user who created the proposal
     * @param salt The salt
     * @param proposalType The proposal type
     *
     * @return validationCode Validation code
     */
    function _validateSalt(
        bytes32 fulfillmentProposalId,
        bytes32 proposalId,
        address user,
        uint256 salt,
        IPredictDotLoan.ProposalType proposalType
    ) private view returns (uint256 validationCode) {
        (bool _lending, bool _borrowing) = PREDICT_DOT_LOAN.saltCancellations(user, salt);
        if (fulfillmentProposalId != bytes32(0)) {
            if (fulfillmentProposalId != proposalId) {
                return SALT_ALREADY_USED;
            }
        }

        if (proposalType == IPredictDotLoan.ProposalType.LoanOffer) {
            if (_lending) {
                return PROPOSAL_CANCELLED;
            }
        } else {
            if (_borrowing) {
                return PROPOSAL_CANCELLED;
            }
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the proposal's nonce matches the signer's nonce
     *
     * @param proposalType The proposal type
     * @param from The user who created the proposal
     * @param nonce The nonce
     *
     * @return validationCode Validation code
     */
    function _validateNonceIsCurrent(
        IPredictDotLoan.ProposalType proposalType,
        address from,
        uint256 nonce
    ) private view returns (uint256 validationCode) {
        (uint256 lendingNonce, uint256 borrowingNonce) = PREDICT_DOT_LOAN.nonces(from);
        if (proposalType == IPredictDotLoan.ProposalType.LoanOffer) {
            if (nonce != lendingNonce) {
                return NONCE_IS_NOT_CURRENT;
            }
        } else {
            if (nonce != borrowingNonce) {
                return NONCE_IS_NOT_CURRENT;
            }
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the proposal's collateralization ratio is equal to or above 100%.
     *
     * @param collateralAmount The proposal's collateral amount
     * @param loanAmount The proposal's loan amount
     *
     * @return validationCode Validation code
     */
    function _validateCollateralizationRatio(
        uint256 collateralAmount,
        uint256 loanAmount
    ) private pure returns (uint256 validationCode) {
        if (collateralAmount < loanAmount) {
            return COLLATERALIZATION_RATIO_BELOW_100;
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the proposal's interest rate is above the minimum interest rate
     *         and below the maximum interest rate.
     *
     * @param interestRatePerSecond The proposal's interest rate
     *
     * @return validationCode Validation code
     */
    function _validateInterestRate(uint256 interestRatePerSecond) private pure returns (uint256 validationCode) {
        if (interestRatePerSecond <= InterestLib.ONE) {
            return INTEREST_RATE_TOO_LOW;
        }

        if (interestRatePerSecond > InterestLib.ONE + InterestLib.TEN_THOUSAND_APY) {
            return INTEREST_RATE_TOO_HIGH;
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the position is tradeable on the exchange or the neg risk CTF exchange.
     *
     * @param proposal The proposal
     */
    function _validatePositionIsTradeable(
        IPredictDotLoan.Proposal calldata proposal
    ) private view returns (uint256 validationCode) {
        uint256 positionId = _derivePositionId(proposal);
        ICTFExchange exchange = proposal.questionType == IPredictDotLoan.QuestionType.Binary
            ? PREDICT_DOT_LOAN.CTF_EXCHANGE()
            : PREDICT_DOT_LOAN.NEG_RISK_CTF_EXCHANGE();
        (uint256 complement, ) = exchange.registry(positionId);
        if (complement == 0) {
            return POSITION_IS_NOT_TRADEABLE;
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the question price is available.
     *
     * @dev We do not allow positions that are already resolved from being used as collaterals for loans
     *      as it is very likely that the position is worth nothing
     *
     * @param questionType The question type
     * @param questionId The question ID
     */
    function _validateQuestionState(
        IPredictDotLoan.QuestionType questionType,
        bytes32 questionId
    ) private view returns (uint256 validationCode) {
        if (questionType == IPredictDotLoan.QuestionType.Binary) {
            validationCode = _validateBinaryOutcomeQuestionPriceUnavailable(
                PREDICT_DOT_LOAN.UMA_CTF_ADAPTER(),
                questionId
            );
        } else {
            if (_isNegRiskMarketDetermined(questionId)) {
                return MARKET_RESOLVED;
            }

            validationCode = _validateBinaryOutcomeQuestionPriceUnavailable(
                PREDICT_DOT_LOAN.NEG_RISK_UMA_CTF_ADAPTER(),
                questionId
            );
        }

        return validationCode;
    }

    /**
     * @notice This function checks if the proposal's protocol fee basis points match the protocol fee basis points set by the admin
     *
     * @param proposalProtocolFeeBasisPoints The proposal's protocol fee basis points
     *
     * @return validationCode Validation code
     */
    function _validateMatchingProtocolFeeBasisPoints(
        uint256 proposalProtocolFeeBasisPoints
    ) private view returns (uint256 validationCode) {
        if (proposalProtocolFeeBasisPoints != protocolFeeBasisPoints) {
            return PROTOCOL_FEE_BASIS_POINTS_MISMATCH;
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the proposal lender has granted sufficient approvals for the loan token.
     *
     * @param proposal The Proposal struct
     * @param lender The proposal's lender
     *
     * @return validationCode Validation code
     */
    function _validateLenderLoanTokenApproval(
        IPredictDotLoan.Proposal calldata proposal,
        address lender
    ) private view returns (uint256 validationCode) {
        if (IERC20(LOAN_TOKEN).allowance(lender, address(PREDICT_DOT_LOAN)) < proposal.loanAmount) {
            return LENDER_INSUFFICIENT_LOAN_TOKEN_APPROVAL;
        }
        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if the proposal borrower granted approval rights to PredictDotLoan.
     *
     * @param borrower The proposal's borrower
     *
     * @return validationCode Validation code
     */
    function _validateBorrowerCollateralTokenApproval(address borrower) private view returns (uint256 validationCode) {
        if (!CTF.isApprovedForAll(borrower, address(PREDICT_DOT_LOAN))) {
            return BORROWER_COLLATERAL_TOKEN_NOT_APPROVED;
        }
        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if a binary outcome question price is unavailable.
     *
     * @param umaCtfAdapter The UMA CTF adapter address
     * @param questionId The question ID
     */
    function _validateBinaryOutcomeQuestionPriceUnavailable(
        address umaCtfAdapter,
        bytes32 questionId
    ) private view returns (uint256 validationCode) {
        (bool isAvailable, bytes4 umaError) = _isBinaryOutcomeQuestionPriceAvailable(umaCtfAdapter, questionId);

        // 0x579a4801 is the error code for PriceNotAvailable()
        if (isAvailable) {
            return QUESTION_RESOLVED;
        } else if (umaError != 0x579a4801) {
            // Loans should still be blocked if the error is NotInitialized, Flagged or Paused
            // Reference: https://github.com/Polymarket/uma-ctf-adapter/blob/main/src/UmaCtfAdapter.sol#L145
            return QUESTION_STATE_ABNORMAL;
        }

        return PROPOSAL_EXPECTED_TO_BE_VALID;
    }

    /**
     * @notice This function checks if a neg risk market is determined.
     *
     * @param oracleRequestId The UMA question ID
     */
    function _isNegRiskMarketDetermined(bytes32 oracleRequestId) private view returns (bool isDetermined) {
        bytes32 questionId = NEG_RISK_OPERATOR.questionIds(oracleRequestId);
        isDetermined = NEG_RISK_ADAPTER.getDetermined(NegRiskIdLib.getMarketId(questionId));
    }

    /**
     * @notice This function checks if a binary outcome question price is available.
     *
     * @param umaCtfAdapter The UMA CTF adapter address
     * @param questionId The question ID
     */
    function _isBinaryOutcomeQuestionPriceAvailable(
        address umaCtfAdapter,
        bytes32 questionId
    ) private view returns (bool isAvailable, bytes4 umaError) {
        try IUmaCtfAdapter(umaCtfAdapter).getExpectedPayouts(questionId) returns (uint256[] memory) {
            isAvailable = true;
        } catch (bytes memory reason) {
            isAvailable = false;
            umaError = bytes4(reason);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the protocol fee basis points. Only callable by admins.
     *
     * @param _protocolFeeBasisPoints The protocol fee basis points
     */
    function updateProtocolFeeBasisPoints(uint8 _protocolFeeBasisPoints) external {
        if (!PREDICT_DOT_LOAN.hasRole(PREDICT_DOT_LOAN.DEFAULT_ADMIN_ROLE(), msg.sender)) {
            revert NotAdmin();
        }
        if (_protocolFeeBasisPoints > MAXIMUM_PROTOCOL_FEE_BASIS_POINTS) {
            revert ProtocolFeeBasisPointsTooHigh();
        }
        protocolFeeBasisPoints = _protocolFeeBasisPoints;
    }

    /*//////////////////////////////////////////////////////////////
                        CONDITIONAL TOKENS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice This function derives the position ID from the proposal.
     *
     * @dev Derive the position ID from the question type, question ID and outcome
     *
     *      The proposal struct does not require positionId directly because it has
     *      to verify the question ID is not already resolved and the position ID actually
     *      comes from the question ID provided. It is more efficient to just derive the
     *      position ID and use it instead of requiring the user to provide it and then
     *      compare it to the derived position ID.
     *
     * @param proposal The Proposal
     */
    function _derivePositionId(IPredictDotLoan.Proposal calldata proposal) private view returns (uint256 positionId) {
        if (proposal.questionType == IPredictDotLoan.QuestionType.Binary) {
            bytes32 conditionId = _getConditionId(PREDICT_DOT_LOAN.UMA_CTF_ADAPTER(), proposal.questionId, 2);
            bytes32 collectionId = CTF.getCollectionId(bytes32(0), conditionId, proposal.outcome ? 1 : 2);
            positionId = _getPositionId(LOAN_TOKEN, collectionId);
        } else {
            positionId = NEG_RISK_ADAPTER.getPositionId(proposal.questionId, proposal.outcome);
        }
    }

    /*//////////////////////////////////////////////////////////////
          LOGIC COPIED FROM CTHelpers FOR PERFORMANCE REASONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice This function gets the condition ID based on the oracle, question ID and outcome slot count.
     *
     * @dev Constructs a condition ID from an oracle, a question ID, and the outcome slot count for the question.
     *
     * @param oracle The account assigned to report the result for the prepared condition.
     * @param questionId An identifier for the question to be answered by the oracle.
     * @param outcomeSlotCount The number of outcome slots which should be used for this condition. Must not exceed 256.
     */
    function _getConditionId(address oracle, bytes32 questionId, uint outcomeSlotCount) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    /**
     * @notice This function gets the position ID based on the collateral token and collection ID.
     *
     * @dev Constructs a position ID from a collateral token and an outcome collection. These IDs are used as the ERC-1155 ID for this contract.
     *
     * @param collateralToken Collateral token which backs the position.
     * @param collectionId ID of the outcome collection associated with this position.
     */
    function _getPositionId(IERC20 collateralToken, bytes32 collectionId) private pure returns (uint) {
        return uint(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }

    /*//////////////////////////////////////////////////////////////
        TO BE REARRANGED STYLISTICALLY ONCE MATCH PROPOSALS IS DONE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice This function checks if the borrow request and loan offer's protocol fee basis points match the protocol fee basis points set by the admin
     *
     * @param borrowRequestProtocolFeeBasisPoints The borrow request's protocol fee basis points
     * @param loanOfferProtocolFeeBasisPoints The loan offer's protocol fee basis points
     *
     * @return validationCode Validation code
     */
    function _validate_matchProposals_ProtocolFeeBasisPoints(
        uint256 borrowRequestProtocolFeeBasisPoints,
        uint256 loanOfferProtocolFeeBasisPoints
    ) private view returns (uint256 validationCode) {
        if (
            (borrowRequestProtocolFeeBasisPoints != protocolFeeBasisPoints) &&
            (loanOfferProtocolFeeBasisPoints != protocolFeeBasisPoints)
        ) {
            return BORROW_REQUEST_AND_LOAN_OFFER_PROTOCOL_FEE_BASIS_POINTS_MISMATCH;
        }

        if (borrowRequestProtocolFeeBasisPoints != protocolFeeBasisPoints) {
            return BORROW_REQUEST_PROTOCOL_FEE_BASIS_POINTS_MISMATCH;
        }

        if (loanOfferProtocolFeeBasisPoints != protocolFeeBasisPoints) {
            return LOAN_OFFER_PROTOCOL_FEE_BASIS_POINTS_MISMATCH;
        }

        return MATCHING_EXPECTED_TO_BE_VALID;
    }
}
