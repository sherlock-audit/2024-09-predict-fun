// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {BlastPredictDotLoan} from "../../contracts/BlastPredictDotLoan.sol";
import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";

import {AddressFinder} from "../mock/AddressFinder.sol";
import {MockBlastPoints} from "../mock/MockBlastPoints.sol";
import {MockBlastYield} from "../mock/MockBlastYield.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockEIP1271Wallet} from "../mock/MockEIP1271Wallet.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";
import {ConditionalTokens} from "../mock/ConditionalTokens/ConditionalTokens.sol";
import {MockCTFExchange} from "../mock/CTFExchange/MockCTFExchange.sol";
import {MockNegRiskAdapter} from "../mock/NegRiskAdapter/MockNegRiskAdapter.sol";
import {MockNegRiskOperator} from "../mock/NegRiskAdapter/MockNegRiskOperator.sol";

import {TestParameters} from "./TestParameters.sol";
import {Test} from "forge-std/Test.sol";

abstract contract AssertionHelpers is Test, TestParameters {
    bytes internal constant SINGLE_OUTCOME_QUESTION = "Adam Cochran for President 2024";
    bytes32 internal questionId = keccak256(SINGLE_OUTCOME_QUESTION);

    bytes internal constant MULTI_OUTCOMES_MARKET = "US Presidential Election Winner 2024";

    bytes internal constant MULTI_OUTCOMES_QUESTION = "Will Adam Cochran become the president in 2024?";
    bytes32 internal negRiskQuestionId = keccak256(MULTI_OUTCOMES_QUESTION);

    uint256 internal constant lenderPrivateKey = 0xA11CE;
    address internal lender = vm.addr(lenderPrivateKey);

    uint256 internal constant lender2PrivateKey = 0xB1;
    address internal lender2 = vm.addr(lender2PrivateKey);

    uint256 internal constant borrowerPrivateKey = 0x777;
    address internal borrower = vm.addr(borrowerPrivateKey);

    uint256 internal constant borrower2PrivateKey = 0xAaaaaaaaa;
    address internal borrower2 = vm.addr(borrower2PrivateKey);

    address internal whiteKnight = address(12);
    address internal owner = address(69);
    address internal blastPointsOperator = address(420);
    address internal bot = address(888);
    // 3 commas club
    address internal protocolFeeRecipient = address(1_000_000_000);

    AddressFinder internal addressFinder;

    MockBlastYield internal mockBlastYield;
    MockBlastPoints internal mockBlastPoints;

    BlastPredictDotLoan internal predictDotLoan;

    MockCTFExchange internal mockCTFExchange;
    MockCTFExchange internal mockNegRiskCTFExchange;

    ConditionalTokens internal mockCTF;

    MockUmaCtfAdapter internal mockUmaCtfAdapter;
    MockUmaCtfAdapter internal mockNegRiskUmaCtfAdapter;

    MockNegRiskAdapter internal mockNegRiskAdapter;
    MockNegRiskOperator internal mockNegRiskOperator;

    MockERC20 internal mockERC20;

    MockEIP1271Wallet internal wallet;

    event LoanCalled(uint256 loanId);
    event LoanDefaulted(uint256 loanId);
    event LoanRefinanced(
        bytes32 proposalId,
        uint256 refinancedLoanId,
        uint256 newLoanId,
        address indexed lender,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 interestRatePerSecond,
        uint256 minimumDuration,
        uint256 protocolFee
    );
    event LoansRefinanced(IPredictDotLoan.RefinancingResult[] results);
    event LoanTransferred(
        uint256 loanId,
        uint256 repaidAmount,
        uint256 protocolFee,
        uint256 newLoanId,
        address newLender,
        uint256 newInterestRatePerSecond
    );
    event MinimumOrderFeeRateUpdated(uint256 _minimumOrderFeeRate);
    event NoncesIncremented(uint256 lendingNonce, uint256 borrowingNonce);

    event ProposalAccepted(
        uint256 loanId,
        bytes32 proposalId,
        address indexed borrower,
        address indexed lender,
        uint256 indexed positionId,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 protocolFee
    );

    event OrderFilledUsingProposal(
        bytes32 proposalId,
        uint256 loanId,
        address indexed borrower,
        address indexed lender,
        uint256 indexed positionId,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 protocolFee
    );

    event ProposalsMatched(
        bytes32 loanOfferProposalId,
        bytes32 borrowRequestProposalId,
        uint256 loanId,
        address indexed borrower,
        address indexed lender,
        uint256 indexed positionId,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 protocolFee
    );
    event AutoRefinancingEnabledToggled(address indexed user, uint256 preference);
    event ProtocolFeeBasisPointsUpdated(uint256 _protocolFeeBasisPoints);
    event ProtocolFeeRecipientUpdated(address _protocolFeeRecipient);
    event SaltsCancelled(address indexed user, IPredictDotLoan.SaltCancellationRequest[] requests);

    function expectEmitCheckAll() internal {
        vm.expectEmit({checkTopic1: true, checkTopic2: true, checkTopic3: true, checkData: true});
    }

    function _assertBalanceAndFulfillmentBeforeExecution(
        address _borrower,
        address _lender,
        IPredictDotLoan.Proposal memory proposal
    ) internal view {
        assertEq(mockERC20.balanceOf(_borrower), 0);
        assertEq(mockCTF.balanceOf(_lender, _getPositionId(true)), 0);
        assertEq(mockERC20.balanceOf(_lender), LOAN_AMOUNT);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), 0);
        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), mockNegRiskAdapter.getPositionId(negRiskQuestionId, true)),
            0
        );
        (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(proposal);
        assertEq(proposalId, bytes32(0));
        assertEq(collateralAmount, 0);
        assertEq(loanAmount, 0);
    }

    function _assertLoanCreated() internal view {
        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            uint256 loanAmount,
            uint256 interestRatePerSecond,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(1);
        assertEq(_borrower, borrower);
        assertEq(_lender, lender);
        assertEq(positionId, _getPositionId(true));
        assertEq(collateralAmount, COLLATERAL_AMOUNT);
        assertEq(loanAmount, LOAN_AMOUNT);
        assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, LOAN_DURATION);
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        assertEq(_getNextLoanId(), 2);
    }

    function _assertLoanCreated_NegRisk() internal view {
        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            uint256 loanAmount,
            uint256 interestRatePerSecond,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(1);
        assertEq(_borrower, borrower);
        assertEq(_lender, lender);
        assertEq(positionId, mockNegRiskAdapter.getPositionId(negRiskQuestionId, true));
        assertEq(collateralAmount, COLLATERAL_AMOUNT);
        assertEq(loanAmount, LOAN_AMOUNT);
        assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, LOAN_DURATION);
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.NegRisk));
        assertEq(_getNextLoanId(), 2);
    }

    function _assertLoanCreated_PartialFulfillmentFirstLeg() internal view {
        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            uint256 loanAmount,
            uint256 interestRatePerSecond,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(1);
        assertEq(_borrower, borrower);
        assertEq(_lender, lender);
        assertEq(positionId, _getPositionId(true));
        assertEq(collateralAmount, COLLATERAL_AMOUNT / 10);
        assertEq(loanAmount, LOAN_AMOUNT / 10);
        assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, LOAN_DURATION);
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        assertEq(_getNextLoanId(), 2);
    }

    function _assertLoanCreated_PartialFulfillmentSecondLeg() internal view {
        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            uint256 loanAmount,
            uint256 interestRatePerSecond,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(2);
        assertEq(_borrower, borrower);
        assertEq(_lender, lender);
        assertEq(positionId, _getPositionId(true));
        assertEq(collateralAmount, (COLLATERAL_AMOUNT * 9) / 10);
        assertEq(loanAmount, (LOAN_AMOUNT * 9) / 10);
        assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, LOAN_DURATION);
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        assertEq(_getNextLoanId(), 3);
    }

    function _assertLoanCreated_Refinanced(
        IPredictDotLoan.QuestionType expectedQuestionType,
        uint256 expectedCollateralAmount,
        uint256 expectedLoanAmount
    ) internal view {
        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            uint256 loanAmount,
            uint256 interestRatePerSecond,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(2);
        assertEq(_borrower, borrower);
        assertEq(_lender, lender2);
        assertEq(uint8(expectedQuestionType), uint8(questionType));
        if (expectedQuestionType == IPredictDotLoan.QuestionType.Binary) {
            assertEq(positionId, _getPositionId(true));
        } else if (expectedQuestionType == IPredictDotLoan.QuestionType.NegRisk) {
            assertEq(positionId, mockNegRiskAdapter.getPositionId(negRiskQuestionId, true));
        }
        assertEq(collateralAmount, expectedCollateralAmount);
        assertEq(loanAmount, expectedLoanAmount);
        assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND - 1);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, LOAN_DURATION * 2);
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(_getNextLoanId(), 3);
    }

    function _assertLoanCreated_OrderFilled(uint256 expectedLoanAmount) internal view {
        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            uint256 loanAmount,
            uint256 interestRatePerSecond,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(1);
        assertEq(_borrower, borrower);
        assertEq(_lender, lender);
        assertEq(positionId, _getPositionId(true));
        assertEq(collateralAmount, COLLATERAL_AMOUNT);
        assertEq(loanAmount, expectedLoanAmount);
        assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, LOAN_DURATION);
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        assertEq(_getNextLoanId(), 2);
        assertEq(mockERC20.allowance(address(predictDotLoan), address(mockCTFExchange)), 0);
    }

    function _assertLoanCreated_NegRisk_OrderFilled(uint256 expectedLoanAmount) internal view {
        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            uint256 loanAmount,
            uint256 interestRatePerSecond,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(1);
        assertEq(_borrower, borrower);
        assertEq(_lender, lender);
        assertEq(positionId, mockNegRiskAdapter.getPositionId(negRiskQuestionId, true));
        assertEq(collateralAmount, COLLATERAL_AMOUNT);
        assertEq(loanAmount, expectedLoanAmount);
        assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, LOAN_DURATION);
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.NegRisk));
        assertEq(_getNextLoanId(), 2);
        assertEq(mockERC20.allowance(address(predictDotLoan), address(mockNegRiskCTFExchange)), 0);
    }

    function _assertLoanCreatedThroughMatchingProposals_FiftyPercent() internal view {
        assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
        assertEq(mockERC20.balanceOf(borrower), LOAN_AMOUNT);
        assertEq(mockERC20.balanceOf(protocolFeeRecipient), 0);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), COLLATERAL_AMOUNT);
        assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), 0);
        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            uint256 loanAmount,
            uint256 _interestRatePerSecond,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(1);
        assertEq(_borrower, borrower);
        assertEq(_lender, lender);
        assertEq(positionId, _getPositionId(true));
        assertEq(collateralAmount, COLLATERAL_AMOUNT / 2);
        assertEq(loanAmount, LOAN_AMOUNT / 2);
        assertEq(_interestRatePerSecond, INTEREST_RATE_PER_SECOND);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, LOAN_DURATION);
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        assertEq(_getNextLoanId(), 3);
    }

    function _assertLoanCreatedThroughMatchingProposals_TwentyFivePercent() internal view {
        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            uint256 loanAmount,
            uint256 _interestRatePerSecond,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(3);
        assertEq(_borrower, borrower);
        assertEq(_lender, lender);
        assertEq(positionId, _getPositionId(true));
        assertEq(collateralAmount, COLLATERAL_AMOUNT / 4);
        assertEq(loanAmount, LOAN_AMOUNT / 4);
        assertEq(_interestRatePerSecond, INTEREST_RATE_PER_SECOND);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, LOAN_DURATION);
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        assertEq(_getNextLoanId(), 4);
    }

    function _assertProposalAcceptedEmitted(bytes32 proposalId, address _borrower, address _lender) internal {
        _assertProposalAcceptedEmitted(proposalId, _borrower, _lender, LOAN_AMOUNT);
    }

    function _assertProposalAcceptedEmitted_NegRisk(bytes32 proposalId, address _borrower, address _lender) internal {
        _assertProposalAcceptedEmitted_NegRisk(proposalId, _borrower, _lender, LOAN_AMOUNT);
    }

    function _assertProposalAcceptedEmitted_NegRisk(
        bytes32 proposalId,
        address _borrower,
        address _lender,
        uint256 loanAmount
    ) internal {
        expectEmitCheckAll();
        emit ProposalAccepted(
            1,
            proposalId,
            _borrower,
            _lender,
            mockNegRiskAdapter.getPositionId(negRiskQuestionId, true),
            COLLATERAL_AMOUNT,
            loanAmount,
            (loanAmount * _getProtocolFeeBasisPoints()) / 10_000
        );
    }

    function _assertProposalAcceptedEmitted(
        bytes32 proposalId,
        address _borrower,
        address _lender,
        uint256 loanAmount
    ) internal {
        expectEmitCheckAll();
        emit ProposalAccepted(
            1,
            proposalId,
            _borrower,
            _lender,
            _getPositionId(true),
            COLLATERAL_AMOUNT,
            loanAmount,
            (loanAmount * _getProtocolFeeBasisPoints()) / 10_000
        );
    }

    function _assertOrderFilledUsingProposal(
        bytes32 proposalId,
        address _borrower,
        address _lender,
        uint256 loanAmount,
        uint256 positionId,
        uint256 protocolFee
    ) internal {
        expectEmitCheckAll();
        emit OrderFilledUsingProposal(
            proposalId,
            1,
            _borrower,
            _lender,
            positionId,
            COLLATERAL_AMOUNT,
            loanAmount,
            protocolFee
        );
    }

    function _assertProposalsMatchedEmitted(
        bytes32 loanOfferProposalId,
        bytes32 borrowRequestProposalId,
        address _borrower,
        address _lender,
        uint256 collateralAmount,
        uint256 loanAmount
    ) internal {
        expectEmitCheckAll();
        emit ProposalsMatched(
            loanOfferProposalId,
            borrowRequestProposalId,
            1,
            _borrower,
            _lender,
            _getPositionId(true),
            collateralAmount,
            loanAmount,
            (loanAmount * _getProtocolFeeBasisPoints()) / 10_000
        );
    }

    function _assertLoanRefinancedEmitted(
        IPredictDotLoan.Proposal memory proposal,
        uint256 collateralAmount,
        uint256 debt
    ) internal {
        uint256 protocolFee = (debt * _getProtocolFeeBasisPoints()) / (10_000 - _getProtocolFeeBasisPoints());
        expectEmitCheckAll();
        emit LoanRefinanced(
            predictDotLoan.hashProposal(proposal),
            1,
            2,
            lender2,
            collateralAmount,
            debt + protocolFee,
            proposal.interestRatePerSecond,
            proposal.duration,
            protocolFee
        );
    }

    function _assertProposalMatchedEmitted_FiftyPercent(
        bytes32 loanOfferProposalId,
        bytes32 borrowRequestProposalId
    ) internal {
        expectEmitCheckAll();
        emit ProposalsMatched(
            loanOfferProposalId,
            borrowRequestProposalId,
            2,
            borrower,
            lender,
            _getPositionId(true),
            COLLATERAL_AMOUNT / 2,
            LOAN_AMOUNT / 2,
            ((LOAN_AMOUNT / 2) * _getProtocolFeeBasisPoints()) / 10_000
        );
    }

    function _assertProposalMatchedEmitted_TwentyFivePercent(
        bytes32 loanOfferProposalId,
        bytes32 borrowRequestProposalId
    ) internal {
        expectEmitCheckAll();
        emit ProposalsMatched(
            loanOfferProposalId,
            borrowRequestProposalId,
            3,
            borrower,
            lender,
            _getPositionId(true),
            COLLATERAL_AMOUNT / 4,
            LOAN_AMOUNT / 4,
            ((LOAN_AMOUNT / 4) * _getProtocolFeeBasisPoints()) / 10_000
        );
    }

    function _assertLoanOfferFulfillmentData(IPredictDotLoan.Proposal memory proposal) internal view {
        (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(proposal);
        assertEq(proposalId, predictDotLoan.hashProposal(proposal));
        assertEq(collateralAmount, proposal.collateralAmount);
        assertEq(loanAmount, proposal.loanAmount);
    }

    function _assertBorrowRequestFulfillmentData(IPredictDotLoan.Proposal memory proposal) internal view {
        (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(proposal);
        assertEq(proposalId, predictDotLoan.hashProposal(proposal));
        assertEq(collateralAmount, proposal.collateralAmount);
        assertEq(loanAmount, proposal.loanAmount);
    }

    function _getPositionId(bool yes) internal view returns (uint256) {
        bytes32 conditionId = mockCTF.getConditionId(address(mockUmaCtfAdapter), questionId, 2);
        bytes32 collectionId = mockCTF.getCollectionId(bytes32(0), conditionId, yes ? 1 : 2);
        return mockCTF.getPositionId(IERC20(address(mockERC20)), collectionId);
    }

    function _getNextLoanId() internal view returns (uint256) {
        return uint256(vm.load(address(predictDotLoan), bytes32(uint256(8))));
    }

    function _getProtocolFeeBasisPoints() internal view returns (uint8) {
        bytes32 slot12 = vm.load(address(predictDotLoan), bytes32(uint256(12)));
        return uint8(uint256(slot12) >> 160);
    }

    function _getMinimumOrderFeeRate() internal view returns (uint16) {
        bytes32 slot12 = vm.load(address(predictDotLoan), bytes32(uint256(12)));
        return uint16(uint256(slot12) >> 168);
    }
}
