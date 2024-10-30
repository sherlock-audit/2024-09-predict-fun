// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";
import {PredictDotLoan_Test} from "./PredictDotLoan.t.sol";

import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";

contract PredictDotLoan_Call_Test is PredictDotLoan_Test {
    function test_call_BinaryOutcomeQuestionIsResolved() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + LOAN_DURATION);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        expectEmitCheckAll();
        emit LoanDefaulted(1);

        vm.prank(lender);
        predictDotLoan.call(1);

        IPredictDotLoan.LoanStatus status = _getLoanStatus(1);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Defaulted));

        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(lender, _getPositionId(true)), COLLATERAL_AMOUNT);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(lender2);
        predictDotLoan.auction(1, 1 ether + 1);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(lender);
        predictDotLoan.seize(1);
    }

    function test_call_NegRiskMarketIsResolved() public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        vm.warp(vm.getBlockTimestamp() + LOAN_DURATION);

        mockNegRiskAdapter.setDetermined(_getNegRiskMarketId(), true);

        expectEmitCheckAll();
        emit LoanDefaulted(1);

        vm.prank(lender);
        predictDotLoan.call(1);

        IPredictDotLoan.LoanStatus status = _getLoanStatus(1);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Defaulted));

        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), mockNegRiskAdapter.getPositionId(negRiskQuestionId, true)),
            0
        );
        assertEq(
            mockCTF.balanceOf(lender, mockNegRiskAdapter.getPositionId(negRiskQuestionId, true)),
            COLLATERAL_AMOUNT
        );

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(lender2);
        predictDotLoan.auction(1, 1 ether + 1);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(lender);
        predictDotLoan.seize(1);
    }

    function test_call_BinaryOutcomeQuestionUnderNegRiskMarketIsResolved() public {
        testFuzz_acceptLoanOffer_NegRisk(0);

        vm.warp(vm.getBlockTimestamp() + LOAN_DURATION);

        mockNegRiskUmaCtfAdapter.setPayoutStatus(negRiskQuestionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        expectEmitCheckAll();
        emit LoanCalled(1);

        vm.prank(lender);
        predictDotLoan.call(1);

        IPredictDotLoan.LoanStatus status = _getLoanStatus(1);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Called));

        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), mockNegRiskAdapter.getPositionId(negRiskQuestionId, true)),
            COLLATERAL_AMOUNT
        );
        assertEq(mockCTF.balanceOf(lender, mockNegRiskAdapter.getPositionId(negRiskQuestionId, true)), 0);
    }

    function testFuzz_call_CollateralizationRatioTooLow(uint24 callTime) public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = ONE + TEN_THOUSAND_APY;
        proposal.signature = _signProposal(proposal);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);

        vm.warp(vm.getBlockTimestamp() + callTime);

        uint256 debt = predictDotLoan.calculateDebt(1);

        vm.assume(debt > COLLATERAL_AMOUNT);

        vm.prank(lender);
        predictDotLoan.call(1);

        IPredictDotLoan.LoanStatus status = _getLoanStatus(1);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Defaulted));

        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(lender, _getPositionId(true)), COLLATERAL_AMOUNT);
    }

    function test_call_RevertIf_UnauthorizedCaller() public {
        testFuzz_acceptLoanOffer(0);

        vm.expectRevert(IPredictDotLoan.UnauthorizedCaller.selector);
        predictDotLoan.call(1);
    }

    function test_call_RevertIf_InvalidLoanStatus() public {
        test_repay_LoanHasNotBeenCalled();

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        vm.prank(lender);
        predictDotLoan.call(1);
    }

    function test_call_RevertIf_LoanNotMatured() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + LOAN_DURATION - 1 seconds);

        vm.expectRevert(IPredictDotLoan.LoanNotMatured.selector);
        vm.prank(lender);
        predictDotLoan.call(1);
    }
}
