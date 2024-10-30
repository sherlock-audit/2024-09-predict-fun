// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";
import {PredictDotLoanValidator} from "../../contracts/PredictDotLoanValidator.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";
import {MockCTFExchange} from "../mock/CTFExchange/MockCTFExchange.sol";
import {MockNegRiskAdapter} from "../mock/NegRiskAdapter/MockNegRiskAdapter.sol";
import {TestHelpers} from "./TestHelpers.sol";
import "../../contracts/ValidationCodeConstants.sol";

contract PredictDotLoanValidator_LoanOffer_Test is TestHelpers {
    PredictDotLoanValidator internal predictDotLoanValidator;

    uint8 private constant PROPOSAL_EXPIRATION_VALIDATION_INDEX = 0;
    uint8 private constant PROPOSAL_LENDER_IS_NOT_BORROWER_VALIDATION_INDEX = 1;
    uint8 private constant PROPOSAL_SIGNATURE_VALIDATION_INDEX = 2;
    uint8 private constant PROPOSAL_FULFILL_AMOUNT_VALIDATION_INDEX = 3;
    uint8 private constant PROPOSAL_SALT_VALIDATION_INDEX = 4;
    uint8 private constant PROPOSAL_NONCE_VALIDATION_INDEX = 5;
    uint8 private constant PROPOSAL_COLLATERALIZATION_RATIO_VALIDATION_INDEX = 6;
    uint8 private constant PROPOSAL_INTEREST_RATE_VALIDATION_INDEX = 7;
    uint8 private constant PROPOSAL_POSITION_TRADABILITY_VALIDATION_INDEX = 8;
    uint8 private constant PROPOSAL_QUESTION_PRICE_VALIDATION_INDEX = 9;
    uint8 private constant PROPOSAL_PROTOCOL_FEE_VALIDATION_INDEX = 10;
    uint8 private constant PROPOSAL_LOAN_TOKEN_APPROVAL_VALIDATION_INDEX = 11;
    uint8 private constant PROPOSAL_COLLATERAL_TOKEN_APPROVAL_VALIDATION_INDEX = 12;
    uint8 private constant TOTAL_VALIDATION_CODES = 13;

    function setUp() public {
        _deploy();

        _mintTokensAndApproveForSetup(LOAN_AMOUNT, COLLATERAL_AMOUNT);

        predictDotLoanValidator = new PredictDotLoanValidator(address(predictDotLoan), 0);
    }

    function test_validateProposal_LoanOffer() public view {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_EXPIRATION_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_LENDER_IS_NOT_BORROWER_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_SIGNATURE_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_FULFILL_AMOUNT_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_SALT_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_NONCE_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_COLLATERALIZATION_RATIO_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_INTEREST_RATE_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_POSITION_TRADABILITY_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_QUESTION_PRICE_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_PROTOCOL_FEE_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_LOAN_TOKEN_APPROVAL_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
        assertEq(validationCodes[PROPOSAL_COLLATERAL_TOKEN_APPROVAL_VALIDATION_INDEX], PROPOSAL_EXPECTED_TO_BE_VALID);
    }

    function test_validateProposal_Expired_LoanOffer() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.warp(vm.getBlockTimestamp() + proposal.validUntil + 1 seconds);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_EXPIRATION_VALIDATION_INDEX], PROPOSAL_EXPIRED);
    }

    function test_validateProposal_LenderIsBorrower_LoanOffer() public view {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            lender,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_LENDER_IS_NOT_BORROWER_VALIDATION_INDEX], LENDER_IS_BORROWER);
    }

    function test_validateProposal_InvalidSignature_LoanOffer() public view {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = address(69);
        proposal.signature = _signProposal(proposal);
        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            lender,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_SIGNATURE_VALIDATION_INDEX], INVALID_SIGNATURE);
    }

    function test_validateProposal_FulfillAmountTooLow_Zero_LoanOffer() public view {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        uint256[13] memory validationCodes = predictDotLoanValidator.validateProposal(proposal, lender, 0);
        assertEq(validationCodes[3], FULFILL_AMOUNT_TOO_LOW);
    }

    function testFuzz_validateProposal_FulfillAmountTooLow_LoanOffer(uint256 amount) public view {
        vm.assume(amount < LOAN_AMOUNT / 10);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            lender,
            amount
        );
        assertEq(validationCodes[PROPOSAL_FULFILL_AMOUNT_VALIDATION_INDEX], FULFILL_AMOUNT_TOO_LOW);
    }

    function testFuzz_validateProposal_FulfillAmountTooHigh_LoanOffer(uint256 amount) public view {
        vm.assume(amount > LOAN_AMOUNT);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            lender,
            amount
        );
        assertEq(validationCodes[PROPOSAL_FULFILL_AMOUNT_VALIDATION_INDEX], FULFILL_AMOUNT_TOO_HIGH);
    }

    function test_validateProposal_Cancelled_LoanOffer() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        _cancelLendingSalt(proposal.from, proposal.salt);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            lender,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_SALT_VALIDATION_INDEX], PROPOSAL_CANCELLED);
    }

    function test_validateProposal_SaltAlreadyUsed_LoanOffer() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);

        IPredictDotLoan.Proposal memory proposalTwo = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposalTwo.loanAmount = LOAN_AMOUNT + 1;
        proposalTwo.salt = proposal.salt;
        proposalTwo.signature = _signProposal(proposalTwo);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposalTwo,
            borrower,
            proposalTwo.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_SALT_VALIDATION_INDEX], SALT_ALREADY_USED);
    }

    function test_validateProposal_LendingNonceIsNotCurrent() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);
        predictDotLoan.incrementNonces(true, false);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            lender,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_NONCE_VALIDATION_INDEX], NONCE_IS_NOT_CURRENT);
    }

    function testFuzz_validateProposal_CollateralizationRatioTooLow_LoanOffer(uint256 collateralAmount) public view {
        vm.assume(collateralAmount < LOAN_AMOUNT);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.collateralAmount = collateralAmount;
        proposal.signature = _signProposal(proposal);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_COLLATERALIZATION_RATIO_VALIDATION_INDEX], COLLATERALIZATION_RATIO_BELOW_100);
    }

    function testFuzz_validateProposal_InterestRateTooLow_LoanOffer(uint256 interestRatePerSecond) public view {
        vm.assume(interestRatePerSecond <= ONE);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = interestRatePerSecond;
        proposal.signature = _signProposal(proposal);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_INTEREST_RATE_VALIDATION_INDEX], INTEREST_RATE_TOO_LOW);
    }

    function testFuzz_validateProposal_InterestRateTooHigh_LoanOffer(uint256 interestRatePerSecond) public view {
        vm.assume(interestRatePerSecond > ONE + TEN_THOUSAND_APY);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = interestRatePerSecond;
        proposal.signature = _signProposal(proposal);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_INTEREST_RATE_VALIDATION_INDEX], INTEREST_RATE_TOO_HIGH);
    }

    function test_validateProposal_PositionIsNotTradeable_LoanOffer() public {
        mockCTFExchange.deregisterToken(_getPositionId(true), _getPositionId(false));
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_POSITION_TRADABILITY_VALIDATION_INDEX], POSITION_IS_NOT_TRADEABLE);
    }

    function test_validateProposal_QuestionResolved_LoanOffer() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_QUESTION_PRICE_VALIDATION_INDEX], QUESTION_RESOLVED);
    }

    function test_validateProposal_MarketResolved_LoanOffer() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);

        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_QUESTION_PRICE_VALIDATION_INDEX], MARKET_RESOLVED);
    }

    function test_validateProposal_QuestionStateAbnormal_LoanOffer() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_QUESTION_PRICE_VALIDATION_INDEX], QUESTION_STATE_ABNORMAL);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        validationCodes = predictDotLoanValidator.validateProposal(proposal, borrower, proposal.loanAmount);
        assertEq(validationCodes[PROPOSAL_QUESTION_PRICE_VALIDATION_INDEX], QUESTION_STATE_ABNORMAL);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        validationCodes = predictDotLoanValidator.validateProposal(proposal, borrower, proposal.loanAmount);
        assertEq(validationCodes[PROPOSAL_QUESTION_PRICE_VALIDATION_INDEX], QUESTION_STATE_ABNORMAL);
    }

    function testFuzz_validateProposal_ProtocolFeeBasisPointsMismatch_LoanOffer(
        uint8 protocolFeeBasisPoints
    ) public view {
        vm.assume(protocolFeeBasisPoints != _getProtocolFeeBasisPoints());

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.protocolFeeBasisPoints = protocolFeeBasisPoints;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(validationCodes[PROPOSAL_PROTOCOL_FEE_VALIDATION_INDEX], PROTOCOL_FEE_BASIS_POINTS_MISMATCH);
    }

    function testFuzz_validateProposal_LenderInsufficientLoanTokenApproval_LoanOffer(uint256 difference) public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        vm.assume(difference >= 1 wei && difference <= proposal.loanAmount);

        vm.prank(proposal.from);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount - difference);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(
            validationCodes[PROPOSAL_LOAN_TOKEN_APPROVAL_VALIDATION_INDEX],
            LENDER_INSUFFICIENT_LOAN_TOKEN_APPROVAL
        );
    }

    function test_validateProposal_BorrowerCollateralTokenNotApproved_LoanOffer() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrower);
        mockCTF.setApprovalForAll(address(predictDotLoan), false);

        uint256[TOTAL_VALIDATION_CODES] memory validationCodes = predictDotLoanValidator.validateProposal(
            proposal,
            borrower,
            proposal.loanAmount
        );
        assertEq(
            validationCodes[PROPOSAL_COLLATERAL_TOKEN_APPROVAL_VALIDATION_INDEX],
            BORROWER_COLLATERAL_TOKEN_NOT_APPROVED
        );
    }

    /*//////////////////////////////////////////////////////////////
                        PROTOCOL FEE LOGIC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateProtocolFeeBasisPoints_LoanOffer() public asPrankedUser(owner) {
        predictDotLoanValidator.updateProtocolFeeBasisPoints(200);
        assertEq(predictDotLoanValidator.protocolFeeBasisPoints(), 200);
    }

    function test_updateProtocolFeeBasisPoints_LoanOffer_NotAdmin() public {
        vm.expectRevert(PredictDotLoanValidator.NotAdmin.selector);
        vm.prank(borrower);
        predictDotLoanValidator.updateProtocolFeeBasisPoints(200);
    }
}
