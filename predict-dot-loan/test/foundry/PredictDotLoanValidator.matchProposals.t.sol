// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";
import {PredictDotLoanValidator} from "../../contracts/PredictDotLoanValidator.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";
import {TestHelpers} from "./TestHelpers.sol";
import "../../contracts/ValidationCodeConstants.sol";

contract PredictDotLoanValidator_MatchProposals_Test is TestHelpers {
    PredictDotLoanValidator internal predictDotLoanValidator;

    uint8 private constant MATCH_PROPOSALS_EXPIRATIONS_VALIDATION_INDEX = 0;
    uint8 private constant MATCH_PROPOSALS_LENDER_IS_NOT_BORROWER_VALIDATION_INDEX = 1;
    uint8 private constant MATCH_PROPOSALS_SIGNATURES_VALIDATION_INDEX = 2;
    uint8 private constant MATCH_PROPOSALS_FULFILL_AMOUNTS_VALIDATION_INDEX = 3;
    uint8 private constant MATCH_PROPOSALS_SALTS_VALIDATION_INDEX = 4;
    uint8 private constant MATCH_PROPOSALS_NONCES_VALIDATION_INDEX = 5;
    uint8 private constant MATCH_PROPOSALS_COLLATERALIZATION_RATIOS_VALIDATION_INDEX = 6;
    uint8 private constant MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX = 7;
    uint8 private constant MATCH_PROPOSALS_POSITION_TRADEABILITY_VALIDATION_INDEX = 8;
    uint8 private constant MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX = 9;
    uint8 private constant MATCH_PROPOSALS_PROPOSAL_TYPES_VALIDATION_INDEX = 10;
    uint8 private constant MATCH_PROPOSALS_PROTOCOL_FEE_BASIS_POINTS_VALIDATION_INDEX = 11;
    uint8 private constant TOTAL_VALIDATION_CODES = 12;

    function setUp() public {
        _deploy();

        _mintTokensAndApproveForSetup(LOAN_AMOUNT * 2, COLLATERAL_AMOUNT * 2);

        predictDotLoanValidator = new PredictDotLoanValidator(address(predictDotLoan), 0);
    }

    function test_validate_matchProposals() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_EXPIRATIONS_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(
            validationCodes[MATCH_PROPOSALS_LENDER_IS_NOT_BORROWER_VALIDATION_INDEX],
            MATCHING_EXPECTED_TO_BE_VALID
        );
        assertEq(validationCodes[MATCH_PROPOSALS_SIGNATURES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_FULFILL_AMOUNTS_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_NONCES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(
            validationCodes[MATCH_PROPOSALS_COLLATERALIZATION_RATIOS_VALIDATION_INDEX],
            MATCHING_EXPECTED_TO_BE_VALID
        );
        assertEq(validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_PROPOSAL_TYPES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(
            validationCodes[MATCH_PROPOSALS_PROTOCOL_FEE_BASIS_POINTS_VALIDATION_INDEX],
            MATCHING_EXPECTED_TO_BE_VALID
        );
    }

    function test_validate_matchProposals_BorrowRequestPartiallyFulfilled() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(borrowRequest, borrowRequest.loanAmount / 2);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_EXPIRATIONS_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(
            validationCodes[MATCH_PROPOSALS_LENDER_IS_NOT_BORROWER_VALIDATION_INDEX],
            MATCHING_EXPECTED_TO_BE_VALID
        );
        assertEq(validationCodes[MATCH_PROPOSALS_SIGNATURES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_FULFILL_AMOUNTS_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_NONCES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(
            validationCodes[MATCH_PROPOSALS_COLLATERALIZATION_RATIOS_VALIDATION_INDEX],
            MATCHING_EXPECTED_TO_BE_VALID
        );
        assertEq(validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_PROPOSAL_TYPES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(
            validationCodes[MATCH_PROPOSALS_PROTOCOL_FEE_BASIS_POINTS_VALIDATION_INDEX],
            MATCHING_EXPECTED_TO_BE_VALID
        );
    }

    function test_validate_matchProposals_LoanOfferPartiallyFulfilled() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(loanOffer, loanOffer.loanAmount / 2);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_EXPIRATIONS_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(
            validationCodes[MATCH_PROPOSALS_LENDER_IS_NOT_BORROWER_VALIDATION_INDEX],
            MATCHING_EXPECTED_TO_BE_VALID
        );
        assertEq(validationCodes[MATCH_PROPOSALS_SIGNATURES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_FULFILL_AMOUNTS_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_NONCES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(
            validationCodes[MATCH_PROPOSALS_COLLATERALIZATION_RATIOS_VALIDATION_INDEX],
            MATCHING_EXPECTED_TO_BE_VALID
        );
        assertEq(validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[MATCH_PROPOSALS_PROPOSAL_TYPES_VALIDATION_INDEX], MATCHING_EXPECTED_TO_BE_VALID);
        assertEq(
            validationCodes[MATCH_PROPOSALS_PROTOCOL_FEE_BASIS_POINTS_VALIDATION_INDEX],
            MATCHING_EXPECTED_TO_BE_VALID
        );
    }

    function test_validate_matchProposals_LoanOffer_Expired() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOffer.validUntil = block.timestamp - 1;
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_EXPIRATIONS_VALIDATION_INDEX], LOAN_OFFER_EXPIRED);
    }

    function test_validate_matchProposals_BorrowRequest_Expired() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        borrowRequest.validUntil = block.timestamp - 1;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_EXPIRATIONS_VALIDATION_INDEX], BORROW_REQUEST_EXPIRED);
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_Expired() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOffer.validUntil = block.timestamp - 1;
        loanOffer.signature = _signProposal(loanOffer);
        borrowRequest.validUntil = block.timestamp - 1;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_EXPIRATIONS_VALIDATION_INDEX], BORROW_REQUEST_AND_LOAN_OFFER_EXPIRED);
    }

    function test_validate_matchProposals_LenderIsBorrower() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.from = lender;
        borrowRequest.signature = _signProposal(borrowRequest);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_LENDER_IS_NOT_BORROWER_VALIDATION_INDEX], LENDER_IS_BORROWER);
    }

    function test_validate_matchProposals_InvalidBorrowRequestSignature() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.from = address(69);
        borrowRequest.signature = _signProposal(borrowRequest);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_SIGNATURES_VALIDATION_INDEX], INVALID_BORROW_REQUEST_SIGNATURE);
    }

    function test_validate_matchProposals_InvalidLoanOfferSignature() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        loanOffer.from = address(69);
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_SIGNATURES_VALIDATION_INDEX], INVALID_LOAN_OFFER_SIGNATURE);
    }

    function test_validate_matchProposals_InvalidBorrowRequestAndLoanOfferSignature() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.from = address(69);
        borrowRequest.signature = _signProposal(borrowRequest);
        loanOffer.from = address(420);
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_SIGNATURES_VALIDATION_INDEX],
            INVALID_BORROW_REQUEST_AND_LOAN_OFFER_SIGNATURE
        );
    }

    function test_validate_matchProposals_LoanOfferFulfillAmountTooLow() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.collateralAmount = COLLATERAL_AMOUNT / 10 - 1 wei;
        borrowRequest.loanAmount = LOAN_AMOUNT / 10 - 1 wei;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_FULFILL_AMOUNTS_VALIDATION_INDEX], LOAN_OFFER_FULFILL_AMOUNT_TOO_LOW);
    }

    function test_validate_matchProposals_BorrowRequestFulfillAmountTooLow() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        loanOffer.collateralAmount = COLLATERAL_AMOUNT / 10 - 1 wei;
        loanOffer.loanAmount = LOAN_AMOUNT / 10 - 1 wei;
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_FULFILL_AMOUNTS_VALIDATION_INDEX],
            BORROW_REQUEST_FULFILL_AMOUNT_TOO_LOW
        );
    }

    function test_validate_matchProposals_PartiallyFulfilledLoanOffer_FulfillAmountTooLow() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.collateralAmount = loanOffer.collateralAmount - 1 wei;
        borrowRequest.loanAmount = loanOffer.loanAmount - 1 wei;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        vm.prank(bot);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_FULFILL_AMOUNTS_VALIDATION_INDEX],
            BORROW_REQUEST_FULFILL_AMOUNT_TOO_LOW
        );
    }

    function test_validate_matchProposals_PartiallyFulfilledBorrowRequest_FulfillAmountTooLow() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        loanOffer.collateralAmount = COLLATERAL_AMOUNT / 2;
        loanOffer.loanAmount = LOAN_AMOUNT / 2;
        loanOffer.signature = _signProposal(loanOffer);

        vm.prank(bot);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_FULFILL_AMOUNTS_VALIDATION_INDEX],
            BORROW_REQUEST_FULFILL_AMOUNT_TOO_LOW
        );
    }

    function test_validate_matchProposals_BorrowRequest_Cancelled() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        _cancelBorrowingSalt(borrowRequest.salt);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX], BORROW_REQUEST_CANCELLED);
    }

    function test_validate_matchProposals_LoanOffer_Cancelled() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        _cancelLendingSalt(loanOffer.from, loanOffer.salt);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX], LOAN_OFFER_CANCELLED);
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_Cancelled() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        _cancelBorrowingSalt(borrowRequest.salt);
        _cancelLendingSalt(loanOffer.from, loanOffer.salt);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX], BORROW_REQUEST_AND_LOAN_OFFER_CANCELLED);
    }

    function test_validate_matchProposals_BorrowRequest_SaltAlreadyUsed() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(borrowRequest, borrowRequest.loanAmount);

        IPredictDotLoan.Proposal memory borrowRequestTwo = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        borrowRequestTwo.loanAmount = LOAN_AMOUNT + 1;
        borrowRequestTwo.salt = borrowRequest.salt;
        borrowRequestTwo.signature = _signProposal(borrowRequestTwo);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequestTwo,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX], BORROW_REQUEST_SALT_ALREADY_USED);
    }

    function test_validate_matchProposals_LoanOffer_SaltAlreadyUsed() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(loanOffer, loanOffer.loanAmount);

        IPredictDotLoan.Proposal memory loanOfferTwo = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOfferTwo.loanAmount = LOAN_AMOUNT + 1;
        loanOfferTwo.salt = loanOffer.salt;
        loanOfferTwo.signature = _signProposal(loanOfferTwo);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOfferTwo
        );
        assertEq(validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX], LOAN_OFFER_SALT_ALREADY_USED);
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_SaltsAlreadyUsed() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(borrowRequest, borrowRequest.loanAmount);

        IPredictDotLoan.Proposal memory borrowRequestTwo = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        borrowRequestTwo.loanAmount = LOAN_AMOUNT + 1;
        borrowRequestTwo.salt = borrowRequest.salt;
        borrowRequestTwo.signature = _signProposal(borrowRequestTwo);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(loanOffer, loanOffer.loanAmount);

        IPredictDotLoan.Proposal memory loanOfferTwo = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOfferTwo.loanAmount = LOAN_AMOUNT + 1;
        loanOfferTwo.salt = loanOffer.salt;
        loanOfferTwo.signature = _signProposal(loanOfferTwo);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequestTwo,
            loanOfferTwo
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_SALTS_ALREADY_USED
        );
    }

    function test_validate_matchProposals_BorrowRequestSaltAlreadyUsedAndLoanOfferCancelled() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(borrowRequest, borrowRequest.loanAmount);

        IPredictDotLoan.Proposal memory borrowRequestTwo = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        borrowRequestTwo.loanAmount = LOAN_AMOUNT + 1;
        borrowRequestTwo.salt = borrowRequest.salt;
        borrowRequestTwo.signature = _signProposal(borrowRequestTwo);

        _cancelLendingSalt(loanOffer.from, loanOffer.salt);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequestTwo,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX],
            BORROW_REQUEST_SALT_ALREADY_USED_AND_LOAN_OFFER_CANCELLED
        );
    }

    function test_validate_matchProposals_BorrowRequestCancelledAndLoanOfferSaltAlreadyUsed() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(loanOffer, loanOffer.loanAmount);

        IPredictDotLoan.Proposal memory loanOfferTwo = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOfferTwo.loanAmount = LOAN_AMOUNT + 1;
        loanOfferTwo.salt = loanOffer.salt;
        loanOfferTwo.signature = _signProposal(loanOfferTwo);

        _cancelBorrowingSalt(borrowRequest.salt);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOfferTwo
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_SALTS_VALIDATION_INDEX],
            LOAN_OFFER_SALT_ALREADY_USED_AND_BORROW_REQUEST_CANCELLED
        );
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_NoncesAreNotCurrent() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);
        predictDotLoan.incrementNonces(true, false);

        vm.prank(borrower);
        predictDotLoan.incrementNonces(false, true);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_NONCES_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_NONCES_ARE_NOT_CURRENT
        );
    }

    function test_validate_matchProposals_BorrowRequest_NoncesIsNotCurrent() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrower);
        predictDotLoan.incrementNonces(false, true);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_NONCES_VALIDATION_INDEX], BORROW_REQUEST_NONCE_IS_NOT_CURRENT);
    }

    function test_validate_matchProposals_LoanOffer_NoncesIsNotCurrent() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);

        predictDotLoan.incrementNonces(true, false);
        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_NONCES_VALIDATION_INDEX], LOAN_OFFER_NONCE_IS_NOT_CURRENT);
    }

    function testFuzz_validate_matchProposals_BorrowRequestAndLoanOffer_CollateralizationRatiosBelow100(
        uint256 borrowRequestCollateralAmount,
        uint256 loanOfferCollateralAmount
    ) public view {
        vm.assume((borrowRequestCollateralAmount < LOAN_AMOUNT) && (loanOfferCollateralAmount < LOAN_AMOUNT));

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.collateralAmount = borrowRequestCollateralAmount;
        loanOffer.collateralAmount = loanOfferCollateralAmount;

        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_COLLATERALIZATION_RATIOS_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_COLLATERALIZATION_RATIOS_BELOW_100
        );
    }

    function testFuzz_validate_matchProposals_BorrowRequest_CollateralizationRatioBelow100(
        uint256 borrowRequestCollateralAmount
    ) public view {
        vm.assume(borrowRequestCollateralAmount < LOAN_AMOUNT);

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.collateralAmount = borrowRequestCollateralAmount;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_COLLATERALIZATION_RATIOS_VALIDATION_INDEX],
            BORROW_REQUEST_COLLATERALIZATION_RATIO_BELOW_100
        );
    }

    function testFuzz_validate_matchProposals_LoanOffer_CollateralizationRatioBelow100(
        uint256 loanOfferCollateralAmount
    ) public view {
        vm.assume(loanOfferCollateralAmount < LOAN_AMOUNT);

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        loanOffer.collateralAmount = loanOfferCollateralAmount;
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_COLLATERALIZATION_RATIOS_VALIDATION_INDEX],
            LOAN_OFFER_COLLATERALIZATION_RATIO_BELOW_100
        );
    }

    function testFuzz_validate_matchProposals_BorrowRequestAndLoanOffer_InterestRatesTooLow(
        uint256 borrowRequestInterestRatePerSecond,
        uint256 loanOfferInterestRatePerSecond
    ) public view {
        vm.assume((borrowRequestInterestRatePerSecond <= ONE) && (loanOfferInterestRatePerSecond <= ONE));

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.interestRatePerSecond = borrowRequestInterestRatePerSecond;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        loanOffer.interestRatePerSecond = loanOfferInterestRatePerSecond;
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_INTEREST_RATES_TOO_LOW
        );
    }

    function testFuzz_validate_matchProposals_BorrowRequestAndLoanOffer_InterestRatesTooHigh(
        uint256 borrowRequestInterestRatePerSecond,
        uint256 loanOfferInterestRatePerSecond
    ) public view {
        vm.assume(
            (borrowRequestInterestRatePerSecond > ONE + TEN_THOUSAND_APY) &&
                (loanOfferInterestRatePerSecond > ONE + TEN_THOUSAND_APY)
        );

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.interestRatePerSecond = borrowRequestInterestRatePerSecond;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        loanOffer.interestRatePerSecond = loanOfferInterestRatePerSecond;
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_INTEREST_RATES_TOO_HIGH
        );
    }

    function testFuzz_validate_matchProposals_BorrowRequest_InterestRateTooLow(
        uint256 borrowRequestInterestRatePerSecond
    ) public view {
        vm.assume(borrowRequestInterestRatePerSecond <= ONE);

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.interestRatePerSecond = borrowRequestInterestRatePerSecond;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX],
            BORROW_REQUEST_INTEREST_RATE_TOO_LOW
        );
    }

    function testFuzz_validate_matchProposals_BorrowRequest_InterestRateTooHigh(
        uint256 borrowRequestInterestRatePerSecond
    ) public view {
        vm.assume(borrowRequestInterestRatePerSecond > ONE + TEN_THOUSAND_APY);

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.interestRatePerSecond = borrowRequestInterestRatePerSecond;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX],
            BORROW_REQUEST_INTEREST_RATE_TOO_HIGH
        );
    }

    function testFuzz_validate_matchProposals_LoanOffer_InterestRateTooLow(
        uint256 loanOfferInterestRatePerSecond
    ) public view {
        vm.assume(loanOfferInterestRatePerSecond <= ONE);

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        loanOffer.interestRatePerSecond = loanOfferInterestRatePerSecond;
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX], LOAN_OFFER_INTEREST_RATE_TOO_LOW);
    }

    function testFuzz_validate_matchProposals_LoanOffer_InterestRateTooHigh(
        uint256 loanOfferInterestRatePerSecond
    ) public view {
        vm.assume(loanOfferInterestRatePerSecond > ONE + TEN_THOUSAND_APY);

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        loanOffer.interestRatePerSecond = loanOfferInterestRatePerSecond;
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX], LOAN_OFFER_INTEREST_RATE_TOO_HIGH);
    }

    function testFuzz_validate_matchProposals_BorrowRequest_InterestRateTooLowAndLoanOffer_InterestRateTooHigh(
        uint256 borrowRequestInterestRatePerSecond,
        uint256 loanOfferInterestRatePerSecond
    ) public view {
        vm.assume(
            (borrowRequestInterestRatePerSecond <= ONE) && (loanOfferInterestRatePerSecond > ONE + TEN_THOUSAND_APY)
        );

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.interestRatePerSecond = borrowRequestInterestRatePerSecond;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        loanOffer.interestRatePerSecond = loanOfferInterestRatePerSecond;
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX],
            BORROW_REQUEST_INTEREST_RATE_TOO_LOW_AND_LOAN_OFFER_INTEREST_RATE_TOO_HIGH
        );
    }

    function testFuzz_validate_matchProposals_BorrowRequest_InterestRateTooHighAndLoanOffer_InterestRateTooLow(
        uint256 borrowRequestInterestRatePerSecond,
        uint256 loanOfferInterestRatePerSecond
    ) public view {
        vm.assume(
            (borrowRequestInterestRatePerSecond > ONE + TEN_THOUSAND_APY) && (loanOfferInterestRatePerSecond <= ONE)
        );

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.interestRatePerSecond = borrowRequestInterestRatePerSecond;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        loanOffer.interestRatePerSecond = loanOfferInterestRatePerSecond;
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_INTEREST_RATES_VALIDATION_INDEX],
            BORROW_REQUEST_INTEREST_RATE_TOO_HIGH_AND_LOAN_OFFER_INTEREST_RATE_TOO_LOW
        );
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_PositionsAreNotTradeable() public {
        mockCTFExchange.deregisterToken(_getPositionId(true), _getPositionId(true));

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_POSITION_TRADEABILITY_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_POSITIONS_ARE_NOT_TRADEABLE
        );
    }

    function test_validate_matchProposals_BorrowRequest_PositionIsNotTradeable() public {
        mockCTFExchange.deregisterToken(_getPositionId(true), _getPositionId(false));

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_POSITION_TRADEABILITY_VALIDATION_INDEX],
            BORROW_REQUEST_POSITION_IS_NOT_TRADEABLE
        );
    }

    function test_validate_matchProposals_LoanOffer_PositionIsNotTradeable() public {
        mockCTFExchange.deregisterToken(_getPositionId(true), _getPositionId(false));

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_POSITION_TRADEABILITY_VALIDATION_INDEX],
            LOAN_OFFER_POSITION_IS_NOT_TRADEABLE
        );
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_QuestionsResolved() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);
        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_QUESTIONS_RESOLVED
        );
    }

    function test_validate_matchProposals_BorrowRequest_QuestionResolved() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX], BORROW_REQUEST_QUESTION_RESOLVED);
    }

    function test_validate_matchProposals_LoanOffer_QuestionResolved() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX], LOAN_OFFER_QUESTION_RESOLVED);
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_MarketResolved() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);

        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_MARKETS_RESOLVED
        );
    }

    function test_validate_matchProposals_BorrowRequest_MarketResolved() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX], BORROW_REQUEST_MARKET_RESOLVED);
    }

    function test_validate_matchProposals_LoanOffer_MarketResolved() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);

        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX], LOAN_OFFER_MARKET_RESOLVED);
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_AbnormalQuestionState() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);
        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL
        );

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);
        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL
        );

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.Paused);
        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL
        );
    }

    function test_validate_matchProposals_BorrowRequest_AbnormalQuestionState() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_STATE_ABNORMAL
        );

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_STATE_ABNORMAL
        );

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_STATE_ABNORMAL
        );
    }

    function test_validate_matchProposals_LoanOffer_AbnormalQuestionStates() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX], LOAN_OFFER_QUESTION_STATE_ABNORMAL);

        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX], LOAN_OFFER_QUESTION_STATE_ABNORMAL);

        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX], LOAN_OFFER_QUESTION_STATE_ABNORMAL);
    }

    function test_validate_matchProposals_BorrowRequest_QuestionResolved_And_LoanOffer_AbnormalQuestionState() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateAlternativeLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);
        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_RESOLVED_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL
        );

        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_RESOLVED_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL
        );

        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_RESOLVED_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL
        );
    }

    function test_validate_matchProposals_BorrowRequest_AbnormalQuestionState_And_LoanOffer_QuestionResolved() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateAlternativeLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);
        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_STATE_ABNORMAL_AND_LOAN_OFFER_QUESTION_RESOLVED
        );

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_STATE_ABNORMAL_AND_LOAN_OFFER_QUESTION_RESOLVED
        );

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_STATE_ABNORMAL_AND_LOAN_OFFER_QUESTION_RESOLVED
        );
    }

    function test_validate_matchProposals_BorrowRequest_QuestionResolved_And_LoanOffer_MarketResolved() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);
        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_RESOLVED_AND_LOAN_OFFER_MARKET_RESOLVED
        );
    }

    function test_validate_matchProposals_BorrowRequest_MarketResolved_And_LoanOffer_QuestionResolved() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);
        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_MARKET_RESOLVED_AND_LOAN_OFFER_QUESTION_RESOLVED
        );
    }

    function test_validate_matchProposals_BorrowRequest_AbnormalQuestionState_And_LoanOffer_MarketResolved() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);
        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_STATE_ABNORMAL_AND_LOAN_OFFER_MARKET_RESOLVED
        );

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_STATE_ABNORMAL_AND_LOAN_OFFER_MARKET_RESOLVED
        );

        mockUmaCtfAdapter.setPayoutStatus(borrowRequest.questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_QUESTION_STATE_ABNORMAL_AND_LOAN_OFFER_MARKET_RESOLVED
        );
    }

    function test_validate_matchProposals_BorrowRequest_MarketResolved_And_LoanOffer_AbnormalQuestionState() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);
        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_MARKET_RESOLVED_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL
        );

        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_MARKET_RESOLVED_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL
        );

        mockUmaCtfAdapter.setPayoutStatus(loanOffer.questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        validationCodes = predictDotLoanValidator.validate_matchProposals(borrowRequest, loanOffer);
        assertEq(
            validationCodes[MATCH_PROPOSALS_QUESTION_STATE_VALIDATION_INDEX],
            BORROW_REQUEST_MARKET_RESOLVED_AND_LOAN_OFFER_QUESTION_STATE_ABNORMAL
        );
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_IncorrectProposalRequestTypes() public view {
        IPredictDotLoan.Proposal memory loanOffer = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_PROPOSAL_TYPES_VALIDATION_INDEX],
            INCORRECT_PROPOSAL_TYPES_FOR_BORROW_REQUEST_AND_LOAN_OFFER
        );
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_IncorrectBorrowRequestType() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_PROPOSAL_TYPES_VALIDATION_INDEX],
            INCORRECT_PROPOSAL_TYPE_FOR_BORROW_REQUEST
        );
    }

    function test_validate_matchProposals_BorrowRequestAndLoanOffer_IncorrectLoanOfferType() public view {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_PROPOSAL_TYPES_VALIDATION_INDEX],
            INCORRECT_PROPOSAL_TYPE_FOR_LOAN_OFFER
        );
    }

    function _generateAlternativeLoanOffer(
        IPredictDotLoan.QuestionType questionType
    ) private view returns (IPredictDotLoan.Proposal memory) {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(questionType);
        loanOffer.questionId = keccak256("Inversebrah for President 2024");
        return loanOffer;
    }

    function testFuzz_validate_matchProposals_BorrowRequestAndLoanOffer_ProtocolFeeBasisPointsMismatch(
        uint8 borrowRequestProtocolFeeBasisPoints,
        uint8 loanOfferProtocolFeeBasisPoints
    ) public view {
        vm.assume(
            (borrowRequestProtocolFeeBasisPoints != _getProtocolFeeBasisPoints()) &&
                (loanOfferProtocolFeeBasisPoints != _getProtocolFeeBasisPoints())
        );

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.protocolFeeBasisPoints = borrowRequestProtocolFeeBasisPoints;
        loanOffer.protocolFeeBasisPoints = loanOfferProtocolFeeBasisPoints;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_PROTOCOL_FEE_BASIS_POINTS_VALIDATION_INDEX],
            BORROW_REQUEST_AND_LOAN_OFFER_PROTOCOL_FEE_BASIS_POINTS_MISMATCH
        );
    }

    function testFuzz_validate_matchProposals_BorrowRequest_ProtocolFeeBasisPointsMismatch(
        uint8 borrowRequestProtocolFeeBasisPoints
    ) public view {
        vm.assume(borrowRequestProtocolFeeBasisPoints != _getProtocolFeeBasisPoints());

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.protocolFeeBasisPoints = borrowRequestProtocolFeeBasisPoints;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_PROTOCOL_FEE_BASIS_POINTS_VALIDATION_INDEX],
            BORROW_REQUEST_PROTOCOL_FEE_BASIS_POINTS_MISMATCH
        );
    }

    function testFuzz_validate_matchProposals_LoanOffer_ProtocolFeeBasisPointsMismatch(
        uint8 loanOfferProtocolFeeBasisPoints
    ) public view {
        vm.assume(loanOfferProtocolFeeBasisPoints != _getProtocolFeeBasisPoints());

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        loanOffer.protocolFeeBasisPoints = loanOfferProtocolFeeBasisPoints;
        loanOffer.signature = _signProposal(loanOffer);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validate_matchProposals(
            borrowRequest,
            loanOffer
        );
        assertEq(
            validationCodes[MATCH_PROPOSALS_PROTOCOL_FEE_BASIS_POINTS_VALIDATION_INDEX],
            LOAN_OFFER_PROTOCOL_FEE_BASIS_POINTS_MISMATCH
        );
    }
}
