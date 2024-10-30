// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";

import {PredictDotLoan_Test} from "./PredictDotLoan.t.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";

contract PredictDotLoan_Refinance_NegRisk_Borrower_Test is PredictDotLoan_Test {
    function testFuzz_refinance_NegRisk_CollateralAmountRequiredIsTheSame(uint8 protocolFeeBasisPoints) public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.NegRisk
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

        _assertLoanCreated_Refinanced(IPredictDotLoan.QuestionType.NegRisk, COLLATERAL_AMOUNT, debt + protocolFee);

        assertEq(mockERC20.balanceOf(lender2), proposal.loanAmount - debt - protocolFee);
        assertEq(mockERC20.balanceOf(lender), debt);
        assertEq(
            mockERC20.balanceOf(protocolFeeRecipient),
            (debt * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
        );

        uint256 positionId = mockNegRiskAdapter.getPositionId(negRiskQuestionId, true);

        assertEq(mockCTF.balanceOf(address(predictDotLoan), positionId), COLLATERAL_AMOUNT);
        assertEq(mockCTF.balanceOf(borrower, positionId), 0);
        assertEq(mockCTF.balanceOf(lender, positionId), 0);
        assertEq(mockCTF.balanceOf(lender2, positionId), 0);
    }

    function testFuzz_refinance_NegRisk_CollateralAmountRequiredIsLessThanOutstandingLoan(
        uint8 protocolFeeBasisPoints
    ) public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_BetterCollateralRatio(
            IPredictDotLoan.QuestionType.NegRisk
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
            IPredictDotLoan.QuestionType.NegRisk,
            expectedCollateralAmount,
            debt + protocolFee
        );

        assertEq(
            mockERC20.balanceOf(lender2),
            proposal.loanAmount - debt - (debt * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
        );
        assertEq(mockERC20.balanceOf(lender), debt);
        assertEq(
            mockERC20.balanceOf(protocolFeeRecipient),
            (debt * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
        );

        uint256 positionId = mockNegRiskAdapter.getPositionId(negRiskQuestionId, true);

        assertEq(mockCTF.balanceOf(address(predictDotLoan), positionId), expectedCollateralAmount);
        assertEq(mockCTF.balanceOf(borrower, positionId), COLLATERAL_AMOUNT - expectedCollateralAmount);
        assertEq(mockCTF.balanceOf(lender, positionId), 0);
        assertEq(mockCTF.balanceOf(lender2, positionId), 0);
    }

    function test_refinance_NegRisk_NoUnexpectedDurationShortening() public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.NegRisk
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

    function testFuzz_refinance_NegRisk_RevertIf_ProtocolFeeBasisPointsMismatch(uint8 protocolFeeBasisPoints) public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        vm.assume(protocolFeeBasisPoints != _getProtocolFeeBasisPoints());

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.NegRisk
        );
        proposal.protocolFeeBasisPoints = protocolFeeBasisPoints;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.ProtocolFeeBasisPointsMismatch.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_NegRisk_RevertIf_MarketResolved() public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.NegRisk
        );

        mockERC20.mint(lender2, proposal.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);

        vm.expectRevert(IPredictDotLoan.MarketResolved.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_NegRisk_RevertIf_PositionIdMismatch() public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.NegRisk
        );
        proposal.questionId = keccak256("Will Adam Cochran become the president in 2028?");
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        mockERC20.mint(lender2, proposal.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_NegRisk_RevertIf_PositionIdMismatch_Zero() public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.NegRisk
        );
        proposal.questionId = bytes32(0);
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        mockERC20.mint(lender2, proposal.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_NegRisk_RevertIf_LenderIsBorrower() public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.NegRisk
        );
        proposal.from = borrower;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        mockERC20.mint(lender2, proposal.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        vm.expectRevert(IPredictDotLoan.LenderIsBorrower.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }

    function test_refinance_NegRisk_RevertIf_InsufficientCollateral() public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.NegRisk
        );
        proposal.collateralAmount = COLLATERAL_AMOUNT + 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.expectRevert(IPredictDotLoan.InsufficientCollateral.selector);
        vm.prank(borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing(1, proposal));
    }
}
