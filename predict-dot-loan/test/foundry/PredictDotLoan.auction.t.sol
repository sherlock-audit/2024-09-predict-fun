// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";
import {PredictDotLoan_Test} from "./PredictDotLoan.t.sol";

import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";

contract PredictDotLoan_Auction_Test is PredictDotLoan_Test {
    function test_auction_RevertIf_InvalidLoanStatus_Active() public {
        testFuzz_acceptLoanOffer(0);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        predictDotLoan.auction(1, 1 ether + 1);
    }

    function test_auction_RevertIf_InvalidLoanStatus_Repaid() public {
        test_repay_LoanHasBeenCalled();

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        predictDotLoan.auction(1, 1 ether + 1);
    }

    function test_auction_RevertIf_InvalidLoanStatus_Auctioned() public {
        testFuzz_auction(AUCTION_DURATION, 0);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        predictDotLoan.auction(1, 1 ether + 1);
    }

    function test_auction_RevertIf_InvalidLoanStatus_Defaulted() public {
        test_seize();

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        predictDotLoan.auction(1, 1 ether + 1);
    }

    function test_auction_RevertIf_AbnormalQuestionState() public {
        test_call();

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        vm.prank(lender2);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.auction(1, 1 ether + 1);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        vm.prank(lender2);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.auction(1, 1 ether + 1);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        vm.prank(lender2);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.auction(1, 1 ether + 1);
    }

    function test_auction_RevertIf_LenderIsBorrower() public {
        test_call();

        vm.warp(vm.getBlockTimestamp() + AUCTION_DURATION);

        uint256 currentInterestRatePerSecond = predictDotLoan.auctionCurrentInterestRatePerSecond(1);

        vm.expectRevert(IPredictDotLoan.LenderIsBorrower.selector);
        vm.prank(borrower);
        predictDotLoan.auction(1, currentInterestRatePerSecond);
    }

    function test_auction_RevertIf_NewLenderIsTheSameAsOldLender() public {
        test_call();

        vm.warp(vm.getBlockTimestamp() + AUCTION_DURATION);

        uint256 currentInterestRatePerSecond = predictDotLoan.auctionCurrentInterestRatePerSecond(1);

        vm.expectRevert(IPredictDotLoan.NewLenderIsTheSameAsOldLender.selector);
        vm.prank(lender);
        predictDotLoan.auction(1, currentInterestRatePerSecond);
    }

    function test_auction_RevertIf_AuctionNotStarted() public {
        test_call();

        vm.expectRevert(IPredictDotLoan.AuctionNotStarted.selector);
        predictDotLoan.auction(1, 1 ether + 1);
    }

    function test_auction_RevertIf_AuctionIsOver() public {
        test_call();

        vm.warp(vm.getBlockTimestamp() + AUCTION_DURATION + 1 seconds);

        vm.expectRevert(IPredictDotLoan.AuctionIsOver.selector);
        predictDotLoan.auction(1, 1 ether + 1);
    }

    function test_auction_RevertIf_CollateralizationRatioTooLow() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.collateralAmount = 710 ether;
        proposal.interestRatePerSecond = ONE + TEN_THOUSAND_APY;
        proposal.signature = _signProposal(proposal);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);

        vm.warp(vm.getBlockTimestamp() + LOAN_DURATION);

        vm.prank(lender);
        predictDotLoan.call(1);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        vm.prank(owner);
        predictDotLoan.updateProtocolFeeBasisPoints(200);

        uint256 currentInterestRatePerSecond = predictDotLoan.auctionCurrentInterestRatePerSecond(1);

        vm.expectRevert(IPredictDotLoan.CollateralizationRatioTooLow.selector);
        predictDotLoan.auction(1, currentInterestRatePerSecond);
    }

    function test_auctionCurrentInterestRatePerSecond() public {
        test_call();

        uint256 lastCurrentInterestRatePerSecond;

        for (uint256 step = 1; step <= 24; step += 1) {
            vm.warp(vm.getBlockTimestamp() + 1 hours);

            uint256 currentInterestRatePerSecond = predictDotLoan.auctionCurrentInterestRatePerSecond(1);

            assertGt(currentInterestRatePerSecond, lastCurrentInterestRatePerSecond);

            lastCurrentInterestRatePerSecond = currentInterestRatePerSecond;
        }
    }

    function testFuzz_auctionCurrentInterestRatePerSecond(uint256 timeElapsed) public {
        vm.assume(timeElapsed > 0 && timeElapsed <= AUCTION_DURATION);

        test_call();

        vm.warp(vm.getBlockTimestamp() + timeElapsed);

        uint256 currentInterestRatePerSecond = predictDotLoan.auctionCurrentInterestRatePerSecond(1);

        assertGt(currentInterestRatePerSecond, ONE);
        assertLe(currentInterestRatePerSecond, ONE + TEN_THOUSAND_APY);
    }

    function test_auctionCurrentInterestRatePerSecond_RevertIf_InvalidLoanStatus() public {
        testFuzz_acceptLoanOffer(0);

        vm.expectRevert(IPredictDotLoan.InvalidLoanStatus.selector);
        predictDotLoan.auctionCurrentInterestRatePerSecond(1);
    }

    function test_auctionCurrentInterestRatePerSecond_RevertIf_AuctionNotStarted() public {
        test_call();

        vm.expectRevert(IPredictDotLoan.AuctionNotStarted.selector);
        predictDotLoan.auctionCurrentInterestRatePerSecond(1);
    }

    function test_auctionCurrentInterestRatePerSecond_RevertIf_AuctionIsOver() public {
        test_call();

        vm.warp(vm.getBlockTimestamp() + AUCTION_DURATION + 1 seconds);

        vm.expectRevert(IPredictDotLoan.AuctionIsOver.selector);
        predictDotLoan.auctionCurrentInterestRatePerSecond(1);
    }

    function testFuzz_auctionCurrentInterestRatePerSecond_RevertIf_InterestRatePerSecondTooHigh(
        uint16 timeElapsed
    ) public {
        vm.assume(timeElapsed > 0);

        test_call();

        vm.warp(vm.getBlockTimestamp() + timeElapsed);

        uint256 currentInterestRatePerSecond = predictDotLoan.auctionCurrentInterestRatePerSecond(1);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooHigh.selector);
        predictDotLoan.auction(1, currentInterestRatePerSecond - 1);
    }
}
