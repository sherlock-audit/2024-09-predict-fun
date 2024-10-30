// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";
import {PredictDotLoan_Test} from "./PredictDotLoan.t.sol";

contract PredictDotLoan_CalculateCollateralAmountRequired_Test is PredictDotLoan_Test {
    function test_calculateCollateralAmountRequired_FullFulfillment() public view {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256 collateralRequired = predictDotLoan.calculateCollateralAmountRequired(proposal, proposal.loanAmount);
        assertEq(collateralRequired, proposal.collateralAmount);
    }

    function test_calculateCollateralAmountRequired_PartialFulfillment() public view {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256 fulfillAmount = proposal.loanAmount / 2;
        uint256 collateralRequired = predictDotLoan.calculateCollateralAmountRequired(proposal, fulfillAmount);
        assertEq(collateralRequired, proposal.collateralAmount / 2);
    }

    function testFuzz_calculateCollateralAmountRequired_PartialFulfillment(uint256 fulfillAmount) public view {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        // Ensure fulfillAmount is within valid range
        vm.assume(fulfillAmount > proposal.loanAmount / 10 && fulfillAmount < proposal.loanAmount);

        uint256 collateralRequired = predictDotLoan.calculateCollateralAmountRequired(proposal, fulfillAmount);

        // Calculate expected collateral amount
        uint256 expectedCollateral = (fulfillAmount * proposal.collateralAmount) / proposal.loanAmount;

        assertEq(collateralRequired, expectedCollateral, "Collateral amount mismatch");
        assertLt(collateralRequired, proposal.collateralAmount, "Collateral should be less than full amount");
        assertGt(collateralRequired, 0, "Collateral should be greater than 0");
    }

    function test_calculateCollateralAmountRequired_PartialFulfillmentAfterPreviousFulfillment() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        // Simulate a previous partial fulfillment
        vm.mockCall(
            address(predictDotLoan),
            abi.encodeWithSelector(IPredictDotLoan.getFulfillment.selector, proposal),
            abi.encode(predictDotLoan.hashProposal(proposal), proposal.collateralAmount / 4, proposal.loanAmount / 4)
        );

        uint256 newFulfillAmount = proposal.loanAmount / 2;
        uint256 collateralRequired = predictDotLoan.calculateCollateralAmountRequired(proposal, newFulfillAmount);

        uint256 expectedCollateral = (newFulfillAmount * proposal.collateralAmount) / proposal.loanAmount;
        assertEq(collateralRequired, expectedCollateral, "Collateral amount mismatch");
    }

    function test_calculateCollateralAmountRequired_FinalFulfillment() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        // Simulate a previous partial fulfillment
        vm.mockCall(
            address(predictDotLoan),
            abi.encodeWithSelector(IPredictDotLoan.getFulfillment.selector, proposal),
            abi.encode(
                predictDotLoan.hashProposal(proposal),
                (proposal.collateralAmount * 6) / 9,
                (proposal.loanAmount * 6) / 9
            )
        );

        uint256 finalFulfillAmount = proposal.loanAmount - (proposal.loanAmount * 6) / 9;
        uint256 collateralRequired = predictDotLoan.calculateCollateralAmountRequired(proposal, finalFulfillAmount);

        uint256 expectedCollateral = proposal.collateralAmount - ((proposal.collateralAmount * 6) / 9);
        assertEq(collateralRequired, expectedCollateral, "Collateral amount mismatch for final fulfillment");
    }

    function test_calculateCollateralAmountRequired_RevertIf_FulfillAmountTooLow_Zero() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        predictDotLoan.calculateCollateralAmountRequired(proposal, 0);
    }

    function test_calculateCollateralAmountRequired_RevertIf_FulfillAmountTooLow() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256 fulfillAmount = proposal.loanAmount / 10 - 1;

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        predictDotLoan.calculateCollateralAmountRequired(proposal, fulfillAmount);
    }

    function test_calculateCollateralAmountRequired_RevertIf_FulfillAmountTooHigh() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256 fulfillAmount = proposal.loanAmount + 1;

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooHigh.selector);
        predictDotLoan.calculateCollateralAmountRequired(proposal, fulfillAmount);
    }

    function test_calculateCollateralAmountRequired_EdgeCase_MinimumFulfillment() public view {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256 fulfillAmount = proposal.loanAmount / 10;

        uint256 collateralRequired = predictDotLoan.calculateCollateralAmountRequired(proposal, fulfillAmount);

        assertEq(collateralRequired, proposal.collateralAmount / 10);
    }

    function test_calculateCollateralAmountRequired_EdgeCase_AlmostFullFulfillment() public view {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256 fulfillAmount = proposal.loanAmount - 1;

        uint256 collateralRequired = predictDotLoan.calculateCollateralAmountRequired(proposal, fulfillAmount);

        assertEq(collateralRequired, (fulfillAmount * proposal.collateralAmount) / proposal.loanAmount);
    }
}
