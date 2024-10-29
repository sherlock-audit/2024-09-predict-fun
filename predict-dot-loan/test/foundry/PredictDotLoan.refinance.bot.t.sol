// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";

import {PredictDotLoan_Test} from "./PredictDotLoan.t.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";

contract PredictDotLoan_Refinance_Bot_Test is PredictDotLoan_Test {
    function testFuzz_refinance_CollateralAmountRequiredIsTheSame(uint8 protocolFeeBasisPoints) public {
        // Only need to mint for one loan as setUp already mints for one loan
        mockERC20.mint(lender, LOAN_AMOUNT);
        _mintCTF(borrower, COLLATERAL_AMOUNT);

        vm.prank(borrower);
        predictDotLoan.toggleAutoRefinancingEnabled();

        vm.prank(lender);
        mockERC20.approve(address(predictDotLoan), LOAN_AMOUNT * 2);

        for (uint256 i; i < 2; i++) {
            IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

            vm.prank(borrower);
            predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
        }

        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal3 = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.Binary
        );

        IPredictDotLoan.Proposal memory proposal4 = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal4.salt = proposal3.salt + 1;
        proposal4.from = lender2;
        proposal4.interestRatePerSecond = INTEREST_RATE_PER_SECOND - 2;
        proposal4.loanAmount =
            EXPECTED_DEBT_AFTER_12_HOURS +
            (EXPECTED_DEBT_AFTER_12_HOURS * protocolFeeBasisPoints) /
            (10_000 - protocolFeeBasisPoints);
        proposal4.duration = LOAN_DURATION * 3;

        proposal3.signature = _signProposal(proposal3, lender2PrivateKey);
        proposal4.signature = _signProposal(proposal4, lender2PrivateKey);

        mockERC20.mint(lender2, proposal3.loanAmount + proposal4.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal3.loanAmount + proposal4.loanAmount);

        {
            IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](2);
            refinancings[0] = IPredictDotLoan.Refinancing(1, proposal3);
            refinancings[1] = IPredictDotLoan.Refinancing(2, proposal4);

            IPredictDotLoan.RefinancingResult[] memory results = new IPredictDotLoan.RefinancingResult[](2);
            results[0] = IPredictDotLoan.RefinancingResult(
                predictDotLoan.hashProposal(proposal3),
                1,
                3,
                lender2,
                COLLATERAL_AMOUNT,
                proposal3.loanAmount,
                proposal3.interestRatePerSecond,
                proposal3.duration,
                (EXPECTED_DEBT_AFTER_12_HOURS * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
            );
            results[1] = IPredictDotLoan.RefinancingResult(
                predictDotLoan.hashProposal(proposal4),
                2,
                4,
                lender2,
                COLLATERAL_AMOUNT,
                proposal4.loanAmount,
                proposal4.interestRatePerSecond,
                proposal4.duration,
                (EXPECTED_DEBT_AFTER_12_HOURS * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
            );

            expectEmitCheckAll();
            emit LoansRefinanced(results);

            vm.prank(bot);
            predictDotLoan.refinance(refinancings);
        }

        assertEq(uint8(_getLoanStatus(1)), uint8(IPredictDotLoan.LoanStatus.Refinanced));
        assertEq(uint8(_getLoanStatus(2)), uint8(IPredictDotLoan.LoanStatus.Refinanced));

        {
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
                IPredictDotLoan.LoanStatus activeLoanStatus,
                IPredictDotLoan.QuestionType questionType
            ) = predictDotLoan.loans(3);

            assertEq(_borrower, borrower);
            assertEq(_lender, lender2);
            assertEq(positionId, _getPositionId(true));
            assertEq(collateralAmount, COLLATERAL_AMOUNT);
            assertEq(loanAmount, proposal3.loanAmount);
            assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND - 1);
            assertEq(startTime, vm.getBlockTimestamp());
            assertEq(minimumDuration, LOAN_DURATION * 2);
            assertEq(callTime, 0);
            assertEq(uint8(activeLoanStatus), uint8(IPredictDotLoan.LoanStatus.Active));
            assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        }

        {
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
                IPredictDotLoan.LoanStatus activeLoanStatus,
                IPredictDotLoan.QuestionType questionType
            ) = predictDotLoan.loans(4);

            assertEq(_borrower, borrower);
            assertEq(_lender, lender2);
            assertEq(positionId, _getPositionId(true));
            assertEq(collateralAmount, COLLATERAL_AMOUNT);
            assertEq(loanAmount, proposal4.loanAmount);
            assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND - 2);
            assertEq(startTime, vm.getBlockTimestamp());
            assertEq(minimumDuration, LOAN_DURATION * 3);
            assertEq(callTime, 0);
            assertEq(uint8(activeLoanStatus), uint8(IPredictDotLoan.LoanStatus.Active));
            assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        }

        assertEq(mockERC20.balanceOf(lender2), 0);
        assertApproxEqAbs(mockERC20.balanceOf(lender), EXPECTED_DEBT_AFTER_12_HOURS * 2, 1);
        assertApproxEqAbs(
            mockERC20.balanceOf(protocolFeeRecipient),
            (EXPECTED_DEBT_AFTER_12_HOURS * 2 * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints),
            1
        );
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), COLLATERAL_AMOUNT * 2);
        assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(lender, _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(lender2, _getPositionId(true)), 0);
    }

    function testFuzz_refinance_CollateralAmountRequiredIsLessThanOutstandingLoan(uint8 protocolFeeBasisPoints) public {
        // Only need to mint for one loan as setUp already mints for one loan
        mockERC20.mint(lender, LOAN_AMOUNT);
        _mintCTF(borrower, COLLATERAL_AMOUNT);

        vm.prank(borrower);
        predictDotLoan.toggleAutoRefinancingEnabled();

        vm.prank(lender);
        mockERC20.approve(address(predictDotLoan), LOAN_AMOUNT * 2);

        for (uint256 i; i < 2; i++) {
            IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

            vm.prank(borrower);
            predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
        }

        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal3 = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal3.from = lender2;
        proposal3.interestRatePerSecond = INTEREST_RATE_PER_SECOND - 1;
        proposal3.loanAmount =
            predictDotLoan.calculateDebt(1) +
            (predictDotLoan.calculateDebt(1) * _getProtocolFeeBasisPoints()) /
            (10_000 - protocolFeeBasisPoints) +
            100 ether;
        proposal3.duration = LOAN_DURATION * 2;

        IPredictDotLoan.Proposal memory proposal4 = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal4.salt = proposal3.salt + 1;
        proposal4.from = lender2;
        proposal4.interestRatePerSecond = INTEREST_RATE_PER_SECOND - 2;
        proposal4.loanAmount =
            predictDotLoan.calculateDebt(2) +
            (predictDotLoan.calculateDebt(2) * _getProtocolFeeBasisPoints()) /
            (10_000 - protocolFeeBasisPoints) +
            100 ether;
        proposal4.duration = LOAN_DURATION * 3;

        proposal3.signature = _signProposal(proposal3, lender2PrivateKey);
        proposal4.signature = _signProposal(proposal4, lender2PrivateKey);

        mockERC20.mint(lender2, proposal3.loanAmount + proposal4.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal3.loanAmount + proposal4.loanAmount);

        {
            IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](2);
            refinancings[0] = IPredictDotLoan.Refinancing(1, proposal3);
            refinancings[1] = IPredictDotLoan.Refinancing(2, proposal4);

            IPredictDotLoan.RefinancingResult[] memory results = new IPredictDotLoan.RefinancingResult[](2);
            results[0] = IPredictDotLoan.RefinancingResult(
                predictDotLoan.hashProposal(proposal3),
                1,
                3,
                lender2,
                (proposal3.collateralAmount * (proposal3.loanAmount - 100 ether)) / proposal3.loanAmount,
                proposal3.loanAmount - 100 ether,
                proposal3.interestRatePerSecond,
                proposal3.duration,
                (EXPECTED_DEBT_AFTER_12_HOURS * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
            );
            results[1] = IPredictDotLoan.RefinancingResult(
                predictDotLoan.hashProposal(proposal4),
                2,
                4,
                lender2,
                (proposal4.collateralAmount * (proposal4.loanAmount - 100 ether)) / proposal4.loanAmount,
                proposal4.loanAmount - 100 ether,
                proposal4.interestRatePerSecond,
                proposal4.duration,
                (EXPECTED_DEBT_AFTER_12_HOURS * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
            );

            expectEmitCheckAll();
            emit LoansRefinanced(results);

            vm.prank(bot);
            predictDotLoan.refinance(refinancings);
        }

        assertEq(uint8(_getLoanStatus(1)), uint8(IPredictDotLoan.LoanStatus.Refinanced));
        assertEq(uint8(_getLoanStatus(2)), uint8(IPredictDotLoan.LoanStatus.Refinanced));

        // Checking proposal 4 first to avoid forge coverage stack too deep
        {
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
                IPredictDotLoan.LoanStatus activeLoanStatus,
                IPredictDotLoan.QuestionType questionType
            ) = predictDotLoan.loans(4);

            assertEq(_borrower, borrower);
            assertEq(_lender, lender2);
            assertEq(positionId, _getPositionId(true));
            assertEq(loanAmount, proposal4.loanAmount - 100 ether);
            assertEq(collateralAmount, (COLLATERAL_AMOUNT * loanAmount) / proposal4.loanAmount);
            assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND - 2);
            assertEq(startTime, vm.getBlockTimestamp());
            assertEq(minimumDuration, LOAN_DURATION * 3);
            assertEq(callTime, 0);
            assertEq(uint8(activeLoanStatus), uint8(IPredictDotLoan.LoanStatus.Active));
            assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        }

        {
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
                IPredictDotLoan.LoanStatus activeLoanStatus,
                IPredictDotLoan.QuestionType questionType
            ) = predictDotLoan.loans(3);

            assertEq(_borrower, borrower);
            assertEq(_lender, lender2);
            assertEq(positionId, _getPositionId(true));
            assertEq(loanAmount, proposal3.loanAmount - 100 ether);
            assertEq(collateralAmount, (COLLATERAL_AMOUNT * loanAmount) / proposal3.loanAmount);
            assertEq(interestRatePerSecond, INTEREST_RATE_PER_SECOND - 1);
            assertEq(startTime, vm.getBlockTimestamp());
            assertEq(minimumDuration, LOAN_DURATION * 2);
            assertEq(callTime, 0);
            assertEq(uint8(activeLoanStatus), uint8(IPredictDotLoan.LoanStatus.Active));
            assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        }

        assertApproxEqAbs(
            mockERC20.balanceOf(lender2),
            proposal3.loanAmount +
                proposal4.loanAmount -
                EXPECTED_DEBT_AFTER_12_HOURS *
                2 -
                ((EXPECTED_DEBT_AFTER_12_HOURS * 2 * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)),
            1
        );
        assertApproxEqAbs(mockERC20.balanceOf(lender), EXPECTED_DEBT_AFTER_12_HOURS * 2, 1);
        assertApproxEqAbs(
            mockERC20.balanceOf(protocolFeeRecipient),
            ((EXPECTED_DEBT_AFTER_12_HOURS * 2) * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints),
            1
        );
        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)),
            (COLLATERAL_AMOUNT * (proposal3.loanAmount - 100 ether)) /
                proposal3.loanAmount +
                (COLLATERAL_AMOUNT * (proposal4.loanAmount - 100 ether)) /
                proposal4.loanAmount
        );
        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)),
            (COLLATERAL_AMOUNT * (proposal3.loanAmount - 100 ether)) /
                proposal3.loanAmount +
                (COLLATERAL_AMOUNT * (proposal4.loanAmount - 100 ether)) /
                proposal4.loanAmount
        );
        assertEq(
            mockCTF.balanceOf(borrower, _getPositionId(true)),
            COLLATERAL_AMOUNT * 2 - mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true))
        );
        assertEq(mockCTF.balanceOf(lender, _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(lender2, _getPositionId(true)), 0);
    }

    function testFuzz_refinance_RevertIf_ProtocolFeeBasisPointsMismatch(uint8 protocolFeeBasisPoints) public {
        testFuzz_acceptLoanOffer(0);

        vm.assume(protocolFeeBasisPoints != _getProtocolFeeBasisPoints());

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.Binary
        );
        proposal.protocolFeeBasisPoints = protocolFeeBasisPoints;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        mockERC20.mint(lender2, proposal.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.prank(borrower);
        predictDotLoan.toggleAutoRefinancingEnabled();

        vm.expectRevert(IPredictDotLoan.ProtocolFeeBasisPointsMismatch.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_BorrowerDidNotEnableAutoRefinancing() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOfferForRefinancing_SameCollateralAmount(
            IPredictDotLoan.QuestionType.Binary
        );

        mockERC20.mint(lender2, proposal.loanAmount);

        vm.prank(lender2);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(abi.encodeWithSelector(IPredictDotLoan.BorrowerDidNotEnableAutoRefinancing.selector, borrower));
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_UnexpectedDurationShortening() public {
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

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.UnexpectedDurationShortening.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_LenderIsBorrower() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = borrower;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.LenderIsBorrower.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_NewLenderIsTheSameAsOldLender() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender;
        proposal.signature = _signProposal(proposal);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.NewLenderIsTheSameAsOldLender.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_AccessControlUnauthorizedAccount() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                lender,
                keccak256("REFINANCIER_ROLE")
            )
        );
        vm.prank(lender);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_NotLoanOffer() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.proposalType = IPredictDotLoan.ProposalType.BorrowRequest;
        proposal.signature = _signProposal(proposal);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.NotLoanOffer.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_InvalidLoanStatus_Called() public {
        test_call();

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_InvalidLoanStatus_Refinanced() public {
        testFuzz_refinance_CollateralAmountRequiredIsTheSame(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_InvalidLoanStatus_Auctioned() public {
        testFuzz_auction(12 hours, 0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_InvalidLoanStatus_Defaulted() public {
        test_seize();

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_Expired() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.validUntil = vm.getBlockTimestamp() - 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.Expired.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_PositionIdMismatch_QuestionTypeMismatch() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.questionType = IPredictDotLoan.QuestionType.NegRisk;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_PositionIdMismatch() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);
        proposal.questionType = IPredictDotLoan.QuestionType.Binary;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_WorseInterestRatePerSecond() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = INTEREST_RATE_PER_SECOND + 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.WorseInterestRatePerSecond.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_InsufficientCollateral() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.collateralAmount = COLLATERAL_AMOUNT + 1;
        proposal.loanAmount = predictDotLoan.calculateDebt(1);
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.InsufficientCollateral.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_FulfillAmountTooLow() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.loanAmount = predictDotLoan.calculateDebt(1) * 10 + 10;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_FulfillAmountTooHigh() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender2;
        proposal.loanAmount = predictDotLoan.calculateDebt(1) - 1;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooHigh.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_CollateralizationRatioTooLow() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.loanAmount = predictDotLoan.calculateDebt(1);
        proposal.collateralAmount = proposal.loanAmount - 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.CollateralizationRatioTooLow.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_ProposalCancelled() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        _cancelLendingSalt(proposal.from, proposal.salt);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.ProposalCancelled.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_InvalidNonce() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        vm.prank(lender2);
        predictDotLoan.incrementNonces(true, false);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.InvalidNonce.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
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

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposalTwo);

        vm.expectRevert(IPredictDotLoan.SaltAlreadyUsed.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_InterestRatePerSecondTooLow() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = ONE - 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooLow.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }

    function test_refinance_RevertIf_InterestRatePerSecondTooHigh() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = ONE + TEN_THOUSAND_APY + 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        IPredictDotLoan.Refinancing[] memory refinancings = new IPredictDotLoan.Refinancing[](1);
        refinancings[0] = IPredictDotLoan.Refinancing(1, proposal);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooHigh.selector);
        vm.prank(bot);
        predictDotLoan.refinance(refinancings);
    }
}
