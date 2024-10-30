// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";

import {PredictDotLoan_Test} from "./PredictDotLoan.t.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";

contract PredictDotLoan_Refinance_Borrower_Test is PredictDotLoan_Test {
    function testFuzz_refinance_CollateralAmountRequiredIsTheSame(uint8 protocolFeeBasisPoints) public {
        testFuzz_acceptLoanOffer(0);

        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.Binary
        );

        mockERC20.mint(lender2, proposal.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        uint256 debt = predictDotLoan.calculateDebt(1);
        uint256 protocolFee = (debt * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints);

        _assertLoanRefinancedEmitted(proposal, COLLATERAL_AMOUNT, debt);

        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));

        assertEq(uint8(_getLoanStatus(1)), uint8(IPredictDotLoan.LoanStatus.Refinanced));

        _assertLoanCreated_Refinanced(IPredictDotLoan.QuestionType.Binary, COLLATERAL_AMOUNT, debt + protocolFee);

        assertEq(mockERC20.balanceOf(lender2), proposal.loanAmount - debt - protocolFee);
        assertEq(mockERC20.balanceOf(lender), debt);
        assertEq(
            mockERC20.balanceOf(protocolFeeRecipient),
            (debt * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
        );
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), COLLATERAL_AMOUNT);
        assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(lender, _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(lender2, _getPositionId(true)), 0);
    }

    function testFuzz_refinance_CollateralAmountRequiredIsLessThanOutstandingLoan(uint8 protocolFeeBasisPoints) public {
        testFuzz_acceptLoanOffer(0);

        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_BetterCollateralRatio(
            IPredictDotLoan.QuestionType.Binary
        );

        mockERC20.mint(lender2, proposal.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        uint256 debt = predictDotLoan.calculateDebt(1);
        uint256 protocolFee = (debt * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints);
        uint256 expectedCollateralAmount = (proposal.collateralAmount * (debt + protocolFee)) / proposal.loanAmount;

        _assertLoanRefinancedEmitted(proposal, expectedCollateralAmount, debt);

        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));

        assertEq(uint8(_getLoanStatus(1)), uint8(IPredictDotLoan.LoanStatus.Refinanced));

        _assertLoanCreated_Refinanced(
            IPredictDotLoan.QuestionType.Binary,
            expectedCollateralAmount,
            debt + protocolFee
        );

        assertEq(mockERC20.balanceOf(lender2), proposal.loanAmount - debt - protocolFee);
        assertEq(mockERC20.balanceOf(lender), debt);
        assertEq(mockERC20.balanceOf(protocolFeeRecipient), protocolFee);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), expectedCollateralAmount);
        assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), COLLATERAL_AMOUNT - expectedCollateralAmount);
        assertEq(mockCTF.balanceOf(lender, _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(lender2, _getPositionId(true)), 0);
    }

    function test_refinance_NoUnexpectedDurationShortening() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.Binary
        );
        // Original loan duration is 1 days, 12 hours has elapsed, 12 hours to go.
        // Making the new minimum duration 12 hours - 1 second so that it should
        // be callable 1 second before the original loan's end time.
        proposal.duration = 12 hours - 1 seconds;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        mockERC20.mint(lender2, proposal.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        uint256 debt = predictDotLoan.calculateDebt(1);

        _assertLoanRefinancedEmitted(proposal, COLLATERAL_AMOUNT, debt);

        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));

        assertEq(uint8(_getLoanStatus(1)), uint8(IPredictDotLoan.LoanStatus.Refinanced));

        (, , , , , , , uint256 minimumDuration, , , ) = predictDotLoan.loans(2);
        assertEq(minimumDuration, proposal.duration);
    }

    function testFuzz_refinance_RevertIf_ProtocolFeeBasisPointsMismatch(uint8 protocolFeeBasisPoints) public {
        testFuzz_acceptLoanOffer(0);

        vm.assume(protocolFeeBasisPoints != _getProtocolFeeBasisPoints());

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.protocolFeeBasisPoints = protocolFeeBasisPoints;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.ProtocolFeeBasisPointsMismatch.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_NotLoanOffer() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.proposalType = IPredictDotLoan.ProposalType.BorrowRequest;
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.NotLoanOffer.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_LenderIsBorrower() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = borrower;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        vm.expectRevert(IPredictDotLoan.LenderIsBorrower.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_NewLenderIsTheSameAsOldLender() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender;
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.NewLenderIsTheSameAsOldLender.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_AbnormalQuestionState() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_QuestionResolved() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        vm.expectRevert(IPredictDotLoan.QuestionResolved.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_PositionIdMismatch() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.questionId = keccak256("Adam Cochran for President 2028");
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_PositionIdMismatch_QuestionIdIsZero() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.questionId = bytes32(0);
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_UnauthorizedCaller() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.UnauthorizedCaller.selector);
        vm.prank(lender);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_InvalidLoanStatus_Called() public {
        test_call();

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_InvalidLoanStatus_Refinanced() public {
        testFuzz_refinance_CollateralAmountRequiredIsTheSame(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_InvalidLoanStatus_Auctioned() public {
        testFuzz_auction(12 hours, 0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_InvalidLoanStatus_Defaulted() public {
        test_seize();

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_Expired() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.validUntil = vm.getBlockTimestamp() - 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.Expired.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_PositionIdMismatch_QuestionTypeMismatch() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.questionType = IPredictDotLoan.QuestionType.NegRisk;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_WorseInterestRatePerSecond() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = INTEREST_RATE_PER_SECOND + 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.WorseInterestRatePerSecond.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_InsufficientCollateral() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.collateralAmount = COLLATERAL_AMOUNT + 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.InsufficientCollateral.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_FulfillAmountTooLow() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.loanAmount = predictDotLoan.calculateDebt(1) * 10 + 10;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_FulfillAmountTooHigh() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.loanAmount = predictDotLoan.calculateDebt(1) - 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooHigh.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_CollateralizationRatioTooLow() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.loanAmount = predictDotLoan.calculateDebt(1);
        proposal.collateralAmount = proposal.loanAmount - 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.CollateralizationRatioTooLow.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_ProposalCancelled() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        _cancelLendingSalt(proposal.from, proposal.salt);

        vm.expectRevert(IPredictDotLoan.ProposalCancelled.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_InvalidNonce() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.prank(lender2);
        predictDotLoan.incrementNonces(true, false);

        vm.expectRevert(IPredictDotLoan.InvalidNonce.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_SaltAlreadyUsed() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Proposal memory proposalTwo = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposalTwo.salt = proposal.salt;
        proposalTwo.validUntil = proposal.validUntil + 1;
        proposalTwo.from = lender2;
        proposalTwo.signature = _signProposal(proposalTwo, lender2PrivateKey);

        mockERC20.mint(lender2, proposal.loanAmount);
        _mintCTF(borrower, COLLATERAL_AMOUNT);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        vm.startPrank(borrower);

        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);

        vm.expectRevert(IPredictDotLoan.SaltAlreadyUsed.selector);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposalTwo));

        vm.stopPrank();
    }

    function test_refinance_RevertIf_InterestRatePerSecondTooLow() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = ONE - 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooLow.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_RevertIf_InterestRatePerSecondTooHigh() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = ONE + TEN_THOUSAND_APY + 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooHigh.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }
}
