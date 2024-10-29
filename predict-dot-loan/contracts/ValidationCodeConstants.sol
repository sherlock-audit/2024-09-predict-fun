// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * 0. No error
 */

/**
 * @dev The proposal expected to be valid.
 */
uint256 constant PROPOSAL_EXPECTED_TO_BE_VALID = 0;

/**
 * @dev The matching of the borrow request and loan offer is expected to be valid.
 */
uint256 constant MATCHING_EXPECTED_TO_BE_VALID = 1;

/**
 * 1. Expiration related codes
 */

/**
 * @dev The lending/borrowing proposal has expired.
 */
uint256 constant PROPOSAL_EXPIRED = 101;

/**
 * @dev The borrow request has expired.
 */
uint256 constant BORROW_REQUEST_EXPIRED = 102;

/**
 * @dev The loan offer has expired.
 */
uint256 constant LOAN_OFFER_EXPIRED = 103;

/**
 * @dev Both the borrow request and loan offer have expired.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_EXPIRED = 104;

/**
 * 2. Caller related codes
 */

/**
 * @dev The proposal's lender cannot be the proposal's borrower.
 */
uint256 constant LENDER_IS_BORROWER = 201;

/**
 * 3. Signature related codes
 */

/**
 * @dev The signature is invalid for the given signer and data hash.
 */
uint256 constant INVALID_SIGNATURE = 301;

/**
 * @dev The signature is invalid for the given signer and data hash on the borrow request.
 */
uint256 constant INVALID_BORROW_REQUEST_SIGNATURE = 302;

/**
 * @dev The signature is invalid for the given signer and data hash on the loan offer.
 */
uint256 constant INVALID_LOAN_OFFER_SIGNATURE = 303;

/**
 * @dev The signatures are invalid for the given signers and data hashes on the loan offer and borrow request.
 */
uint256 constant INVALID_BORROW_REQUEST_AND_LOAN_OFFER_SIGNATURE = 304;

/**
 * 4. Fulfillment related codes
 */

/**
 * @dev The fulfill amount was too low.
 */
uint256 constant FULFILL_AMOUNT_TOO_LOW = 401;

/**
 * @dev The fulfill amount was too high.
 */
uint256 constant FULFILL_AMOUNT_TOO_HIGH = 402;

/**
 * @dev The borrow request's fulfill amount was too low.
 */
uint256 constant BORROW_REQUEST_FULFILL_AMOUNT_TOO_LOW = 403;

/**
 * @dev The loan offer's fulfill amount was too low.
 */
uint256 constant LOAN_OFFER_FULFILL_AMOUNT_TOO_LOW = 404;

/**
 * 5. Salt related codes
 */

/**
 * @dev The proposal was cancelled.
 */
uint256 constant PROPOSAL_CANCELLED = 501;

/**
 * @dev The borrow request was cancelled.
 */
uint256 constant BORROW_REQUEST_CANCELLED = 502;

/**
 * @dev The loan offer was cancelled.
 */
uint256 constant LOAN_OFFER_CANCELLED = 503;

/**
 * @dev The borrow request and loan offer were cancelled.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_CANCELLED = 504;

/**
 * @dev The salt was used by another proposal.
 */
uint256 constant SALT_ALREADY_USED = 511;

/**
 * @dev The borrow request salt was used by another proposal.
 */
uint256 constant BORROW_REQUEST_SALT_ALREADY_USED = 512;

/**
 * @dev The loan offer salt was used by another proposal.
 */
uint256 constant LOAN_OFFER_SALT_ALREADY_USED = 513;

/**
 * @dev The borrow request and loan offer salts were used by other proposals.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_SALTS_ALREADY_USED = 514;

/**
 * @dev The borrow request's salt was already used and the loan offer was cancelled.
 */
uint256 constant BORROW_REQUEST_SALT_ALREADY_USED_AND_LOAN_OFFER_CANCELLED = 521;

/**
 * @dev The loan offer's salt was already used and the borrow request was cancelled.
 */
uint256 constant LOAN_OFFER_SALT_ALREADY_USED_AND_BORROW_REQUEST_CANCELLED = 522;

/**
 * 6. Nonce related codes
 */

/**
 * @dev The nonce is not current.
 */
uint256 constant NONCE_IS_NOT_CURRENT = 601;

/**
 * @dev The borrow request's nonce is not current.
 */
uint256 constant BORROW_REQUEST_NONCE_IS_NOT_CURRENT = 602;

/**
 * @dev The loan offer's nonce is not current.
 */
uint256 constant LOAN_OFFER_NONCE_IS_NOT_CURRENT = 603;

/**
 * @dev The borrow request's nonce and loan offer's nonce are not current.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_NONCES_ARE_NOT_CURRENT = 604;

/**
 * 7. Collateral related codes
 */

/**
 * @dev The collateralization ratio is below 100%.
 */
uint256 constant COLLATERALIZATION_RATIO_BELOW_100 = 701;

/**
 * @dev The borrow request's collateralization ratio is below 100%.
 */
uint256 constant BORROW_REQUEST_COLLATERALIZATION_RATIO_BELOW_100 = 702;

/**
 * @dev The loan offer's collateralization ratio is below 100%.
 */
uint256 constant LOAN_OFFER_COLLATERALIZATION_RATIO_BELOW_100 = 703;

/**
 * @dev The borrow request and loan offer's collateralization ratios are below 100%.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_COLLATERALIZATION_RATIOS_BELOW_100 = 704;

/**
 * 8. Interest rate related codes
 */

/**
 * @dev The interest rate is below the minimum interest rate.
 */
uint256 constant INTEREST_RATE_TOO_LOW = 801;

/**
 * @dev The interest rate is above the maximum interest rate.
 */
uint256 constant INTEREST_RATE_TOO_HIGH = 802;

/**
 * @dev The borrow request's interest rate is below the minimum interest rate.
 */
uint256 constant BORROW_REQUEST_INTEREST_RATE_TOO_LOW = 803;

/**
 * @dev The borrow request's interest rate is above the maximum interest rate.
 */
uint256 constant BORROW_REQUEST_INTEREST_RATE_TOO_HIGH = 804;

/**
 * @dev The loan offer's interest rate is below the minimum interest rate.
 */
uint256 constant LOAN_OFFER_INTEREST_RATE_TOO_LOW = 805;

/**
 * @dev The loan offer's interest rate is above the maximum interest rate.
 */
uint256 constant LOAN_OFFER_INTEREST_RATE_TOO_HIGH = 806;

/**
 * @dev The borrow request and loan offer's interest rates are below the minimum interest rate.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_INTEREST_RATES_TOO_LOW = 807;

/**
 * @dev The borrow request and loan offer's interest rates are above the maximum interest rate.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_INTEREST_RATES_TOO_HIGH = 808;

/**
 * @dev The borrow request's interest rate is below the minimum interest rate and the loan offer's interest rate is above the maximum interest rate.
 */
uint256 constant BORROW_REQUEST_INTEREST_RATE_TOO_LOW_AND_LOAN_OFFER_INTEREST_RATE_TOO_HIGH = 809;

/**
 * @dev The borrow request's interest rate is above the maximum interest rate and the loan offer's interest rate is below the minimum interest rate.
 */
uint256 constant BORROW_REQUEST_INTEREST_RATE_TOO_HIGH_AND_LOAN_OFFER_INTEREST_RATE_TOO_LOW = 810;

/**
 * 9. Tradeability related codes
 */

/**
 * @dev The position is not tradeable.
 */
uint256 constant POSITION_IS_NOT_TRADEABLE = 901;

/**
 * @dev The borrow request's position is not tradeable.
 */
uint256 constant BORROW_REQUEST_POSITION_IS_NOT_TRADEABLE = 902;

/**
 * @dev The loan offer's position is not tradeable.
 */
uint256 constant LOAN_OFFER_POSITION_IS_NOT_TRADEABLE = 903;

/**
 * @dev The borrow request and loan offer's positions are not tradeable.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_POSITIONS_ARE_NOT_TRADEABLE = 904;

/**
 * 10. Question state related codes
 */

/**
 * @dev The question is resolved.
 */
uint256 constant QUESTION_RESOLVED = 1_001;

/**
 * @dev The borrow request's question was resolved.
 */
uint256 constant BORROW_REQUEST_QUESTION_RESOLVED = 1_002;

/**
 * @dev The loan offer's question was resolved.
 */
uint256 constant LOAN_OFFER_QUESTION_RESOLVED = 1_003;

/**
 * @dev The borrow request and loan offer's questions were resolved.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_QUESTIONS_RESOLVED = 1_004;

/**
 * @dev The market is resolved.
 */
uint256 constant MARKET_RESOLVED = 1_005;

/**
 * @dev The borrow request's market was resolved.
 */
uint256 constant BORROW_REQUEST_MARKET_RESOLVED = 1_006;

/**
 * @dev The loan offer's market was resolved.
 */
uint256 constant LOAN_OFFER_MARKET_RESOLVED = 1_007;

/**
 * @dev The borrow request and loan offer's markets were resolved.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_MARKETS_RESOLVED = 1_008;

/**
 * @dev The question state is abnormal.
 */
uint256 constant QUESTION_STATE_ABNORMAL = 1_009;

/**
 * @dev The borrow request's question state is abnormal.
 */
uint256 constant BORROW_REQUEST_QUESTION_STATE_ABNORMAL = 1_010;

/**
 * @dev The loan offer's question state is abnormal.
 */
uint256 constant LOAN_OFFER_QUESTION_STATE_ABNORMAL = 1_011;

/**
 * @dev The borrow request and loan offer's question states are abnormal.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL = 1_012;

/**
 * @dev The borrow request's question is resolved and the loan offer's question state is abnormal.
 */
uint256 constant BORROW_REQUEST_QUESTION_RESOLVED_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL = 1_013;

/**
 * @dev The borrow request's question state is abnormal and the loan offer's question is resolved.
 */
uint256 constant BORROW_REQUEST_QUESTION_STATE_ABNORMAL_AND_LOAN_OFFER_QUESTION_RESOLVED = 1_014;

/**
 * @dev The borrow request's question is resolved and the loan offer's market is resolved.
 */
uint256 constant BORROW_REQUEST_QUESTION_RESOLVED_AND_LOAN_OFFER_MARKET_RESOLVED = 1_015;

/**
 * @dev The borrow request's market is resolved and the loan offer's question is resolved.
 */
uint256 constant BORROW_REQUEST_MARKET_RESOLVED_AND_LOAN_OFFER_QUESTION_RESOLVED = 1_016;

/**
 * @dev The borrow request's question state is abnormal and the loan offer's market is resolved.
 */
uint256 constant BORROW_REQUEST_QUESTION_STATE_ABNORMAL_AND_LOAN_OFFER_MARKET_RESOLVED = 1_017;

/**
 * @dev The borrow request's market is resolved and the loan offer's question state is abnormal.
 */
uint256 constant BORROW_REQUEST_MARKET_RESOLVED_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL = 1_018;

/**
 * 11. Protocol fee related codes
 */

/**
 * @dev The protocol fee basis points do not match.
 */
uint256 constant PROTOCOL_FEE_BASIS_POINTS_MISMATCH = 1_101;

/**
 * 12. Token approval related codes
 */

/**
 * @dev The lender has not granted sufficient approvals for the loan token.
 */
uint256 constant LENDER_INSUFFICIENT_LOAN_TOKEN_APPROVAL = 1_201;

/**
 * @dev The borrower has not granted collateral token approval to PredictDotLoan.
 */
uint256 constant BORROWER_COLLATERAL_TOKEN_NOT_APPROVED = 1_202;

/**
 * 13. Proposal Type related codes
 */

/**
 * @dev The proposal types are incorrect for both the borrow request and loan offer to be matched.
 */
uint256 constant INCORRECT_PROPOSAL_TYPES_FOR_BORROW_REQUEST_AND_LOAN_OFFER = 1_301;

/**
 * @dev The proposal type is incorrect for the borrow request.
 */
uint256 constant INCORRECT_PROPOSAL_TYPE_FOR_BORROW_REQUEST = 1_302;

/**
 * @dev The proposal type is incorrect for the loan offer.
 */
uint256 constant INCORRECT_PROPOSAL_TYPE_FOR_LOAN_OFFER = 1_303;

/*//////////////////////////////////////////////////////////////
    TO BE REARRANGED STYLISTICALLY ONCE MATCH PROPOSALS IS DONE
//////////////////////////////////////////////////////////////*/

/**
 * @dev The borrow request's protocol fee basis points do not match.
 */
uint256 constant BORROW_REQUEST_PROTOCOL_FEE_BASIS_POINTS_MISMATCH = 1_102;

/**
 * @dev The loan offer's protocol fee basis points do not match.
 */
uint256 constant LOAN_OFFER_PROTOCOL_FEE_BASIS_POINTS_MISMATCH = 1_103;

/**
 * @dev The borrow request and loan offer's protocol fee basis points do not match.
 */
uint256 constant BORROW_REQUEST_AND_LOAN_OFFER_PROTOCOL_FEE_BASIS_POINTS_MISMATCH = 1_104;
