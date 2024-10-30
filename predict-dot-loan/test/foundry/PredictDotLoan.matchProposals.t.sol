// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";

import {PredictDotLoan_Test} from "./PredictDotLoan.t.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";
import {ConditionalTokens} from "../mock/ConditionalTokens/ConditionalTokens.sol";

contract PredictDotLoan_MatchProposals_Test is PredictDotLoan_Test {
    function testFuzz_matchProposals(uint8 protocolFeeBasisPoints) public {
        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, loanOffer);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, borrowRequest);

        _assertProposalsMatchedEmitted(
            predictDotLoan.hashProposal(loanOffer),
            predictDotLoan.hashProposal(borrowRequest),
            borrower,
            lender,
            COLLATERAL_AMOUNT,
            LOAN_AMOUNT
        );

        vm.prank(protocolFeeBasisPoints % 2 == 0 ? borrower : lender);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        _assertBorrowRequestFulfillmentData(borrowRequest);
        _assertLoanOfferFulfillmentData(loanOffer);

        assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
        assertEq(
            mockERC20.balanceOf(borrower),
            loanOffer.loanAmount - (loanOffer.loanAmount * protocolFeeBasisPoints) / 10_000
        );
        assertEq(mockERC20.balanceOf(protocolFeeRecipient), (loanOffer.loanAmount * protocolFeeBasisPoints) / 10_000);

        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), loanOffer.collateralAmount);
        assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), 0);

        _assertLoanCreated();
    }

    function testFuzz_matchProposals_LoanOfferHasLowerInterestRatePerSecond(uint32 difference) public {
        vm.assume(difference > 0 && difference < TEN_PERCENT_APY);

        {
            IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
            loanOffer.interestRatePerSecond = INTEREST_RATE_PER_SECOND - difference;
            loanOffer.signature = _signProposal(loanOffer);

            IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

            _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, loanOffer);

            _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, borrowRequest);

            _assertProposalsMatchedEmitted(
                predictDotLoan.hashProposal(loanOffer),
                predictDotLoan.hashProposal(borrowRequest),
                borrower,
                lender,
                COLLATERAL_AMOUNT,
                LOAN_AMOUNT
            );

            vm.prank(difference % 2 == 0 ? borrower : lender);
            predictDotLoan.matchProposals(borrowRequest, loanOffer);

            _assertBorrowRequestFulfillmentData(borrowRequest);
            _assertLoanOfferFulfillmentData(loanOffer);

            assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
            assertEq(mockERC20.balanceOf(borrower), loanOffer.loanAmount);
            assertEq(mockERC20.balanceOf(protocolFeeRecipient), 0);

            assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), loanOffer.collateralAmount);
            assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), 0);
        }

        {
            (, , , , , uint256 _interestRatePerSecond, , , , , ) = predictDotLoan.loans(1);

            assertEq(_interestRatePerSecond, INTEREST_RATE_PER_SECOND - difference);
        }

        {
            (
                address _borrower,
                address _lender,
                uint256 positionId,
                uint256 collateralAmount,
                uint256 loanAmount,
                ,
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
            assertEq(startTime, vm.getBlockTimestamp());
            assertEq(minimumDuration, LOAN_DURATION);
            assertEq(callTime, 0);
            assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
            assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        }

        assertEq(_getNextLoanId(), 2);
    }

    function testFuzz_matchProposals_LoanOfferHasLongerDuration(uint256 duration) public {
        vm.assume(duration > LOAN_DURATION);

        {
            IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
            loanOffer.duration = duration;
            loanOffer.signature = _signProposal(loanOffer);

            IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

            _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, loanOffer);
            _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, borrowRequest);
            _assertProposalsMatchedEmitted(
                predictDotLoan.hashProposal(loanOffer),
                predictDotLoan.hashProposal(borrowRequest),
                borrower,
                lender,
                COLLATERAL_AMOUNT,
                LOAN_AMOUNT
            );

            vm.prank(duration % 2 == 0 ? borrower : lender);
            predictDotLoan.matchProposals(borrowRequest, loanOffer);

            _assertBorrowRequestFulfillmentData(borrowRequest);
            _assertLoanOfferFulfillmentData(loanOffer);

            assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
            assertEq(mockERC20.balanceOf(borrower), loanOffer.loanAmount);
            assertEq(mockERC20.balanceOf(protocolFeeRecipient), 0);
            assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), loanOffer.collateralAmount);
            assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), 0);
        }

        {
            (, , , , , , , uint256 minimumDuration, , , ) = predictDotLoan.loans(1);
            assertEq(minimumDuration, duration);
        }

        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            uint256 loanAmount,
            uint256 _interestRatePerSecond,
            uint256 startTime,
            ,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(1);

        assertEq(_borrower, borrower);
        assertEq(_lender, lender);
        assertEq(positionId, _getPositionId(true));
        assertEq(collateralAmount, COLLATERAL_AMOUNT);
        assertEq(loanAmount, LOAN_AMOUNT);
        assertEq(_interestRatePerSecond, INTEREST_RATE_PER_SECOND);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));

        assertEq(_getNextLoanId(), 2);
    }

    function test_matchProposals_LoanOfferHasLowerCollateralizationRatio() public {
        {
            IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
            loanOffer.collateralAmount = (COLLATERAL_AMOUNT * 9) / 10;
            loanOffer.signature = _signProposal(loanOffer);

            IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

            _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, loanOffer);

            _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, borrowRequest);

            _assertProposalsMatchedEmitted(
                predictDotLoan.hashProposal(loanOffer),
                predictDotLoan.hashProposal(borrowRequest),
                borrower,
                lender,
                loanOffer.collateralAmount,
                LOAN_AMOUNT
            );

            vm.prank(bot);
            predictDotLoan.matchProposals(borrowRequest, loanOffer);

            (bytes32 proposalId, uint256 _collateralAmount, uint256 _loanAmount) = predictDotLoan.getFulfillment(
                loanOffer
            );
            assertEq(proposalId, predictDotLoan.hashProposal(loanOffer));
            assertEq(_collateralAmount, loanOffer.collateralAmount);
            assertEq(_loanAmount, borrowRequest.loanAmount);

            _assertLoanOfferFulfillmentData(loanOffer);

            assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
            assertEq(mockERC20.balanceOf(borrower), loanOffer.loanAmount);
            assertEq(mockERC20.balanceOf(protocolFeeRecipient), 0);

            assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), loanOffer.collateralAmount);
            assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), COLLATERAL_AMOUNT - loanOffer.collateralAmount);
        }

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
        assertEq(collateralAmount, (COLLATERAL_AMOUNT * 9) / 10);
        assertEq(loanAmount, LOAN_AMOUNT);
        assertEq(_interestRatePerSecond, INTEREST_RATE_PER_SECOND);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, LOAN_DURATION);
        assertEq(callTime, 0);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));

        assertEq(_getNextLoanId(), 2);
    }

    function test_matchProposals_BorrowRequestPartiallyFulfilled() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, loanOffer);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, borrowRequest);

        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(borrowRequest, borrowRequest.loanAmount / 2);

        _assertProposalMatchedEmitted_FiftyPercent(
            predictDotLoan.hashProposal(loanOffer),
            predictDotLoan.hashProposal(borrowRequest)
        );

        vm.prank(bot);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        _assertBorrowRequestFulfillmentData(borrowRequest);

        (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(loanOffer);
        assertEq(proposalId, predictDotLoan.hashProposal(loanOffer));
        assertEq(collateralAmount, loanOffer.collateralAmount / 2);
        assertEq(loanAmount, loanOffer.loanAmount / 2);

        _assertLoanCreatedThroughMatchingProposals_FiftyPercent();
    }

    function test_matchProposals_LoanOfferPartiallyFulfilled() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, loanOffer);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, borrowRequest);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(loanOffer, loanOffer.loanAmount / 2);

        _assertProposalMatchedEmitted_FiftyPercent(
            predictDotLoan.hashProposal(loanOffer),
            predictDotLoan.hashProposal(borrowRequest)
        );

        vm.prank(bot);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        _assertLoanOfferFulfillmentData(loanOffer);

        (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(
            borrowRequest
        );
        assertEq(proposalId, predictDotLoan.hashProposal(borrowRequest));
        assertEq(collateralAmount, borrowRequest.collateralAmount / 2);
        assertEq(loanAmount, borrowRequest.loanAmount / 2);

        _assertLoanCreatedThroughMatchingProposals_FiftyPercent();
    }

    function test_matchProposals_BothPartiallyFulfilled_BorrowRequestHasMoreCapacity() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        mockERC20.mint(lender2, borrowRequest.loanAmount / 2);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), borrowRequest.loanAmount / 2);

        vm.prank(borrower2);
        mockCTF.setApprovalForAll(address(predictDotLoan), true);

        _mintCTF(borrower2, COLLATERAL_AMOUNT);

        vm.prank(lender2);
        predictDotLoan.acceptBorrowRequest(borrowRequest, borrowRequest.loanAmount / 2);

        vm.prank(borrower2);
        predictDotLoan.acceptLoanOffer(loanOffer, (loanOffer.loanAmount * 3) / 4);

        {
            (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(
                borrowRequest
            );
            assertEq(proposalId, predictDotLoan.hashProposal(borrowRequest));
            assertEq(collateralAmount, borrowRequest.collateralAmount / 2);
            assertEq(loanAmount, borrowRequest.loanAmount / 2);
        }

        {
            (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(
                loanOffer
            );
            assertEq(proposalId, predictDotLoan.hashProposal(loanOffer));
            assertEq(collateralAmount, (loanOffer.collateralAmount * 3) / 4);
            assertEq(loanAmount, (loanOffer.loanAmount * 3) / 4);
        }

        _assertProposalMatchedEmitted_TwentyFivePercent(
            predictDotLoan.hashProposal(loanOffer),
            predictDotLoan.hashProposal(borrowRequest)
        );

        vm.prank(bot);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        _assertLoanOfferFulfillmentData(loanOffer);

        {
            (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(
                borrowRequest
            );
            assertEq(proposalId, predictDotLoan.hashProposal(borrowRequest));
            assertEq(collateralAmount, borrowRequest.collateralAmount / 2 + loanOffer.collateralAmount / 4);
            assertEq(loanAmount, borrowRequest.loanAmount / 2 + loanOffer.loanAmount / 4);
        }

        assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
        assertEq(mockERC20.balanceOf(borrower), borrowRequest.loanAmount / 2 + loanOffer.loanAmount / 4);
        assertEq(mockERC20.balanceOf(lender), 0);
        assertEq(mockERC20.balanceOf(protocolFeeRecipient), 0);

        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), 1_500 ether);
        assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), COLLATERAL_AMOUNT / 4);

        _assertLoanCreatedThroughMatchingProposals_TwentyFivePercent();
    }

    function test_matchProposals_BothPartiallyFulfilled_LoanOfferHasMoreCapacity() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        mockERC20.mint(lender2, (borrowRequest.loanAmount * 3) / 4);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), (borrowRequest.loanAmount * 3) / 4);

        vm.prank(borrower2);
        mockCTF.setApprovalForAll(address(predictDotLoan), true);

        _mintCTF(borrower2, COLLATERAL_AMOUNT);

        vm.prank(lender2);
        predictDotLoan.acceptBorrowRequest(borrowRequest, (borrowRequest.loanAmount * 3) / 4);

        vm.prank(borrower2);
        predictDotLoan.acceptLoanOffer(loanOffer, loanOffer.loanAmount / 2);

        {
            (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(
                borrowRequest
            );
            assertEq(proposalId, predictDotLoan.hashProposal(borrowRequest));
            assertEq(collateralAmount, (borrowRequest.collateralAmount * 3) / 4);
            assertEq(loanAmount, (borrowRequest.loanAmount * 3) / 4);
        }

        {
            (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(
                loanOffer
            );
            assertEq(proposalId, predictDotLoan.hashProposal(loanOffer));
            assertEq(collateralAmount, loanOffer.collateralAmount / 2);
            assertEq(loanAmount, loanOffer.loanAmount / 2);
        }

        _assertProposalMatchedEmitted_TwentyFivePercent(
            predictDotLoan.hashProposal(loanOffer),
            predictDotLoan.hashProposal(borrowRequest)
        );

        vm.prank(bot);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        _assertBorrowRequestFulfillmentData(borrowRequest);

        {
            (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(
                loanOffer
            );
            assertEq(proposalId, predictDotLoan.hashProposal(loanOffer));
            assertEq(collateralAmount, borrowRequest.collateralAmount / 4 + loanOffer.collateralAmount / 2);
            assertEq(loanAmount, borrowRequest.loanAmount / 4 + loanOffer.loanAmount / 2);
        }

        assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
        assertEq(mockERC20.balanceOf(borrower), (borrowRequest.loanAmount * 3) / 4 + loanOffer.loanAmount / 4);
        assertEq(mockERC20.balanceOf(lender), loanOffer.loanAmount / 4);
        assertEq(mockERC20.balanceOf(protocolFeeRecipient), 0);

        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), 1_500 ether);
        assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), 0);

        _assertLoanCreatedThroughMatchingProposals_TwentyFivePercent();
    }

    function test_matchProposals_CollateralizationRatioShouldNotDeviate() public {
        // Collateral ratio: 20 / 10 = 200%
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        borrowRequest.collateralAmount = 20 ether;
        borrowRequest.loanAmount = 10 ether;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        // Collateral ratio: 5 / 5 = 100%
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOffer.collateralAmount = 5 ether;
        loanOffer.loanAmount = 5 ether;
        loanOffer.signature = _signProposal(loanOffer, lenderPrivateKey);

        vm.prank(bot);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(borrowRequest, 5 ether);

        (, , , uint256 collateralAmount, uint256 loanAmount, , , , , , ) = predictDotLoan.loans(1);

        assertEq((collateralAmount * 1e18) / loanAmount, 1e18);

        (, , , collateralAmount, loanAmount, , , , , , ) = predictDotLoan.loans(2);

        assertEq((collateralAmount * 1e18) / loanAmount, 2e18);
    }

    function test_matchProposals_RevertIf_AccessControlUnauthorizedAccount() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(address(420));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                address(420),
                keccak256("PROPOSALS_MATCHER_ROLE")
            )
        );
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function testFuzz_matchProposals_RevertIf_ProtocolFeeBasisPointsMismatch_LoanOffer(
        uint8 protocolFeeBasisPoints
    ) public {
        vm.assume(protocolFeeBasisPoints != _getProtocolFeeBasisPoints());

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        loanOffer.protocolFeeBasisPoints = protocolFeeBasisPoints;
        loanOffer.signature = _signProposal(loanOffer);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.ProtocolFeeBasisPointsMismatch.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function testFuzz_matchProposals_RevertIf_ProtocolFeeBasisPointsMismatch_BorrowRequest(
        uint8 protocolFeeBasisPoints
    ) public {
        vm.assume(protocolFeeBasisPoints != _getProtocolFeeBasisPoints());

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.protocolFeeBasisPoints = protocolFeeBasisPoints;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.ProtocolFeeBasisPointsMismatch.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_LenderIsBorrower() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.from = lender;
        borrowRequest.signature = _signProposal(borrowRequest);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.LenderIsBorrower.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_FulfillAmountTooLow_BorrowRequest() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.collateralAmount = COLLATERAL_AMOUNT / 11;
        borrowRequest.loanAmount = LOAN_AMOUNT / 11;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_FulfillAmountTooLow_LoanOffer() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        loanOffer.collateralAmount = COLLATERAL_AMOUNT / 11;
        loanOffer.loanAmount = LOAN_AMOUNT / 11;
        loanOffer.signature = _signProposal(loanOffer);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_FulfillAmountTooLow_BorrowRequestFulfilled() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.collateralAmount = COLLATERAL_AMOUNT / 2;
        borrowRequest.loanAmount = LOAN_AMOUNT / 2;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        vm.prank(bot);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_FulfillAmountTooLow_LoanOfferFulfilled() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        loanOffer.collateralAmount = COLLATERAL_AMOUNT / 2;
        loanOffer.loanAmount = LOAN_AMOUNT / 2;
        loanOffer.signature = _signProposal(loanOffer);

        vm.prank(bot);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_NotBorrowRequest() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.NotBorrowRequest.selector);
        predictDotLoan.matchProposals(loanOffer, loanOffer);
    }

    function test_matchProposals_RevertIf_NotLoanOffer() public {
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.NotLoanOffer.selector);
        predictDotLoan.matchProposals(borrowRequest, borrowRequest);
    }

    function test_matchProposals_RevertIf_NoQuestionIdForOracleRequestId() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);

        mockNegRiskOperator.setQuestionId(negRiskQuestionId, bytes32(0));

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.NoQuestionIdForOracleRequestId.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_PositionIdMismatch() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_PositionIdMismatch_PositionIdMismatch_ThroughQuestionType() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function testFuzz_matchProposals_RevertIf_UnacceptableCollateralizationRatio(uint256 delta) public {
        vm.assume(delta > 0 && delta < LOAN_AMOUNT);

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        loanOffer.loanAmount = borrowRequest.loanAmount - delta;

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.UnacceptableCollateralizationRatio.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_UnacceptableDuration() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        loanOffer.duration = borrowRequest.duration - 1;

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.UnacceptableDuration.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_UnacceptableInterestRatePerSecond() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        loanOffer.interestRatePerSecond = borrowRequest.interestRatePerSecond + 1;

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.UnacceptableInterestRatePerSecond.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_Expired_LoanOffer() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOffer.validUntil = block.timestamp - 1;
        loanOffer.signature = _signProposal(loanOffer);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.Expired.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_Expired_BorrowRequest() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        borrowRequest.validUntil = block.timestamp - 1;
        borrowRequest.signature = _signProposal(loanOffer);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.Expired.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_InvalidSignature_SignerIsNotMaker_LoanOffer() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOffer.from = address(69);
        loanOffer.signature = _signProposal(loanOffer);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_InvalidSignature_SignerIsNotMaker_BorrowRequest() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        borrowRequest.from = address(69);
        borrowRequest.signature = _signProposal(borrowRequest);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_InvalidSignature_ECDSAInvalidSignature_LoanOffer() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOffer.signature = new bytes(65);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_InvalidSignature_ECDSAInvalidSignature_BorrowRequest() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        borrowRequest.signature = new bytes(65);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_InvalidSignature_ECDSAInvalidSignatureLength_LoanOffer() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOffer.signature = new bytes(69);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_InvalidSignature_ECDSAInvalidSignatureLength_BorrowRequest() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        borrowRequest.signature = new bytes(69);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_ProposalCancelled_LoanOffer() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        IPredictDotLoan.SaltCancellationRequest[] memory requests = new IPredictDotLoan.SaltCancellationRequest[](1);
        requests[0] = IPredictDotLoan.SaltCancellationRequest(loanOffer.salt, true, false);

        vm.prank(loanOffer.from);
        predictDotLoan.cancel(requests);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.ProposalCancelled.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_ProposalCancelled_BorrowRequest() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        IPredictDotLoan.SaltCancellationRequest[] memory requests = new IPredictDotLoan.SaltCancellationRequest[](1);
        requests[0] = IPredictDotLoan.SaltCancellationRequest(borrowRequest.salt, false, true);

        vm.prank(borrowRequest.from);
        predictDotLoan.cancel(requests);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.ProposalCancelled.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_InvalidNonce_LoanOffer() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(loanOffer.from);
        predictDotLoan.incrementNonces(true, false);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InvalidNonce.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_InvalidNonce_BorrowRequest() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrowRequest.from);
        predictDotLoan.incrementNonces(false, true);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InvalidNonce.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_CollateralizationRatioTooLow_LoanOffer() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        loanOffer.loanAmount = loanOffer.collateralAmount + 1;

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.CollateralizationRatioTooLow.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_CollateralizationRatioTooLow_BorrowRequest() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.loanAmount = borrowRequest.collateralAmount + 1;

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.CollateralizationRatioTooLow.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function testFuzz_matchProposals_RevertIf_InterestRatePerSecondTooLow_LoanOffer(
        uint256 interestRatePerSecond
    ) public {
        vm.assume(interestRatePerSecond <= ONE);

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        loanOffer.interestRatePerSecond = interestRatePerSecond;

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooLow.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function testFuzz_matchProposals_RevertIf_InterestRatePerSecondTooLow_BorrowRequest(
        uint256 interestRatePerSecond
    ) public {
        vm.assume(interestRatePerSecond <= ONE);

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.interestRatePerSecond = interestRatePerSecond;

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooLow.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function testFuzz_matchProposals_RevertIf_InterestRatePerSecondTooHigh_LoanOffer(
        uint256 interestRatePerSecond
    ) public {
        vm.assume(interestRatePerSecond > ONE + TEN_THOUSAND_APY);

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        loanOffer.interestRatePerSecond = interestRatePerSecond;

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooHigh.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function testFuzz_matchProposals_RevertIf_InterestRatePerSecondTooHigh_BorrowRequest(
        uint256 interestRatePerSecond
    ) public {
        vm.assume(interestRatePerSecond > ONE + TEN_THOUSAND_APY);

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        borrowRequest.interestRatePerSecond = interestRatePerSecond;

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooHigh.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_PositionIdNotTradeableOnExchange() public {
        mockCTFExchange.deregisterToken(_getPositionId(true), _getPositionId(false));

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.PositionIdNotTradeableOnExchange.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_PositionIdNotTradeableOnExchange_NegRisk() public {
        mockNegRiskCTFExchange.deregisterToken(
            mockNegRiskAdapter.getPositionId(negRiskQuestionId, true),
            mockNegRiskAdapter.getPositionId(negRiskQuestionId, false)
        );

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.PositionIdNotTradeableOnExchange.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_QuestionResolved() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.QuestionResolved.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_AbnormalQuestionState() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_MarketResolved() public {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);

        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.MarketResolved.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_SaltAlreadyUsed_BorrowRequest() public {
        testFuzz_acceptBorrowRequest(0);

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        borrowRequest.collateralAmount *= 2;
        borrowRequest.loanAmount *= 2;
        borrowRequest.salt = 1;
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.SaltAlreadyUsed.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }

    function test_matchProposals_RevertIf_SaltAlreadyUsed_LoanOffer() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        loanOffer.collateralAmount *= 2;
        loanOffer.loanAmount *= 2;
        loanOffer.salt = 1;
        loanOffer.signature = _signProposal(loanOffer);

        vm.prank(bot);
        vm.expectRevert(IPredictDotLoan.SaltAlreadyUsed.selector);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);
    }
}
