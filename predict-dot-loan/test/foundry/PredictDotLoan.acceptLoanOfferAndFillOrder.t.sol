// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {YieldMode, GasMode} from "../../contracts/interfaces/IBlast.sol";
import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";
import {Order, Side} from "../../contracts/interfaces/ICTFExchange.sol";

import {TestHelpers} from "./TestHelpers.sol";

import {Auth} from "../mock/CTFExchange/Auth.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";

contract PredictDotLoan_AcceptLoanOfferAndFillOrder_Test is TestHelpers {
    function setUp() public {
        _deploy();

        mockERC20.mint(lender, LOAN_AMOUNT);

        vm.prank(lender);
        mockERC20.approve(address(predictDotLoan), LOAN_AMOUNT);

        vm.startPrank(borrower);
        mockCTF.setApprovalForAll(address(predictDotLoan), true);
        vm.stopPrank();

        _mintCTF(whiteKnight, COLLATERAL_AMOUNT);

        vm.startPrank(whiteKnight);
        mockCTF.setApprovalForAll(address(mockCTFExchange), true);
        mockCTF.setApprovalForAll(address(mockNegRiskCTFExchange), true);
        mockCTF.setApprovalForAll(address(mockNegRiskAdapter), true);
        vm.stopPrank();
    }

    function testFuzz_acceptLoanOfferAndFillOrder(uint8 protocolFeeBasisPoints) public {
        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        Order memory order = _createMockCTFSellOrder();

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256 protocolFee = (order.takerAmount * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints);
        proposal.loanAmount = order.takerAmount + protocolFee;
        proposal.signature = _signProposal(proposal);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        _assertOrderFilledUsingProposal(
            predictDotLoan.hashProposal(proposal),
            borrower,
            lender,
            proposal.loanAmount,
            _getPositionId(true),
            protocolFee
        );

        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
        assertEq(mockERC20.balanceOf(borrower), 0);
        assertEq(mockERC20.balanceOf(whiteKnight), order.takerAmount);
        assertEq(
            mockERC20.balanceOf(protocolFeeRecipient),
            (order.takerAmount * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
        );
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        _assertLoanOfferFulfillmentData(proposal);

        _assertLoanCreated_OrderFilled(proposal.loanAmount);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_NonZeroOrderFeeRateWithZeroMinimumOrderFeeRate(
        uint16 orderFeeRateBps
    ) public {
        vm.assume(orderFeeRateBps > 0 && orderFeeRateBps <= 50);

        uint8 protocolFeeBasisPoints = 50;

        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        vm.prank(owner);
        predictDotLoan.updateMinimumOrderFeeRate(0);

        Order memory order = _createMockCTFSellOrder();
        order.feeRateBps = orderFeeRateBps;

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256 protocolFee = (order.takerAmount * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints);
        proposal.loanAmount = order.takerAmount + protocolFee;
        proposal.signature = _signProposal(proposal);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        _assertOrderFilledUsingProposal(
            predictDotLoan.hashProposal(proposal),
            borrower,
            lender,
            proposal.loanAmount,
            _getPositionId(true),
            protocolFee
        );

        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
        assertEq(mockERC20.balanceOf(borrower), 0);
        assertEq(mockERC20.balanceOf(whiteKnight), order.takerAmount);
        assertEq(
            mockERC20.balanceOf(protocolFeeRecipient),
            (order.takerAmount * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
        );
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        _assertLoanOfferFulfillmentData(proposal);

        _assertLoanCreated_OrderFilled(proposal.loanAmount);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_OrderFeeRateIsGreaterThanMinimumOrderFeeRate(
        uint16 minimumOrderFeeRate
    ) public {
        vm.assume(minimumOrderFeeRate > 0 && minimumOrderFeeRate <= 50);

        uint8 protocolFeeBasisPoints = 50;

        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        vm.prank(owner);
        predictDotLoan.updateMinimumOrderFeeRate(minimumOrderFeeRate);

        Order memory order = _createMockCTFSellOrder();
        order.feeRateBps = minimumOrderFeeRate * 2;

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256 protocolFee = (order.takerAmount * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints);
        proposal.loanAmount = order.takerAmount + protocolFee;
        proposal.signature = _signProposal(proposal);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        _assertOrderFilledUsingProposal(
            predictDotLoan.hashProposal(proposal),
            borrower,
            lender,
            proposal.loanAmount,
            _getPositionId(true),
            protocolFee
        );

        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
        assertEq(mockERC20.balanceOf(borrower), 0);
        assertGt(
            mockERC20.balanceOf(protocolFeeRecipient),
            (order.takerAmount * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
        );
        uint256 protocolFeesNotRefunded = mockERC20.balanceOf(protocolFeeRecipient) -
            (order.takerAmount * protocolFeeBasisPoints) /
            (10_000 - protocolFeeBasisPoints);
        assertGt(protocolFeesNotRefunded, 0);
        assertEq(mockERC20.balanceOf(whiteKnight), order.takerAmount - protocolFeesNotRefunded);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        _assertLoanOfferFulfillmentData(proposal);

        _assertLoanCreated_OrderFilled(proposal.loanAmount);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_NegRisk(uint8 protocolFeeBasisPoints) public {
        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        _mintNegRiskCTF(whiteKnight, COLLATERAL_AMOUNT);

        // mock CTF exchange does not check signature
        Order memory order = _createOrder(
            whiteKnight,
            mockNegRiskAdapter.getPositionId(negRiskQuestionId, true),
            COLLATERAL_AMOUNT,
            COLLATERAL_AMOUNT / 2, // 50c
            Side.SELL
        );

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);
        uint256 protocolFee = (order.takerAmount * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints);
        proposal.loanAmount = order.takerAmount + protocolFee;
        proposal.signature = _signProposal(proposal);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        _assertOrderFilledUsingProposal(
            predictDotLoan.hashProposal(proposal),
            borrower,
            lender,
            proposal.loanAmount,
            mockNegRiskAdapter.getPositionId(negRiskQuestionId, true),
            protocolFee
        );

        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
        assertEq(mockERC20.balanceOf(borrower), 0);
        assertEq(mockERC20.balanceOf(whiteKnight), order.takerAmount);
        assertEq(
            mockERC20.balanceOf(protocolFeeRecipient),
            (order.takerAmount * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
        );
        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), mockNegRiskAdapter.getPositionId(negRiskQuestionId, true)),
            proposal.collateralAmount
        );
        _assertLoanOfferFulfillmentData(proposal);

        _assertLoanCreated_NegRisk_OrderFilled(proposal.loanAmount);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_ExcessCollateral(uint8 protocolFeeBasisPoints) public {
        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        _mintCTF(whiteKnight, COLLATERAL_AMOUNT);

        Order memory order = _createMockCTFSellOrder();
        order.makerAmount = order.makerAmount * 2;

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        uint256 protocolFee = (order.takerAmount * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints);
        proposal.loanAmount = order.takerAmount + protocolFee;
        proposal.signature = _signProposal(proposal);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        _assertOrderFilledUsingProposal(
            predictDotLoan.hashProposal(proposal),
            borrower,
            lender,
            proposal.loanAmount,
            _getPositionId(true),
            protocolFee
        );

        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
        assertEq(mockERC20.balanceOf(borrower), 0);
        assertEq(mockERC20.balanceOf(whiteKnight), order.takerAmount);
        assertEq(
            mockERC20.balanceOf(protocolFeeRecipient),
            (order.takerAmount * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
        );
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), proposal.collateralAmount);
        _assertLoanOfferFulfillmentData(proposal);

        _assertLoanCreated_OrderFilled(proposal.loanAmount);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_RevertIf_SellerMustBeThirdParty_LenderIsSeller() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        order.maker = proposal.from;

        vm.expectRevert(IPredictDotLoan.SellerMustBeThirdParty.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_RevertIf_SellerMustBeThirdParty_BorrowerIsSeller() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        vm.expectRevert(IPredictDotLoan.SellerMustBeThirdParty.selector);
        vm.prank(order.maker);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_RevertIf_ProtocolFeeBasisPointsMismatch(
        uint8 protocolFeeBasisPoints
    ) public {
        vm.assume(protocolFeeBasisPoints != _getProtocolFeeBasisPoints());
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.loanAmount =
            order.takerAmount +
            (order.takerAmount * protocolFeeBasisPoints) /
            (10_000 - protocolFeeBasisPoints);
        proposal.protocolFeeBasisPoints = protocolFeeBasisPoints;
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.ProtocolFeeBasisPointsMismatch.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrder_RevertIf_OrderFeeRateTooLow() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        vm.prank(owner);
        predictDotLoan.updateMinimumOrderFeeRate(uint16(order.feeRateBps + 1));

        vm.expectRevert(IPredictDotLoan.OrderFeeRateTooLow.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrder_RevertIf_LenderIsBorrower() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        vm.expectRevert(IPredictDotLoan.LenderIsBorrower.selector);
        vm.prank(lender);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrder_RevertIf_NotOperator() public {
        vm.prank(owner);
        mockCTFExchange.removeOperator(address(predictDotLoan));

        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        vm.expectRevert(Auth.NotOperator.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrder_RevertIf_NotLoanOffer() public {
        Order memory order = _createMockCTFSellOrder();

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.loanAmount = order.takerAmount;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        vm.expectRevert(IPredictDotLoan.NotLoanOffer.selector);
        vm.prank(lender);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrder_RevertIf_PositionIdMismatch_OrderTokenIdIsNotLoanOfferPositionId()
        public
    {
        Order memory order = _createMockCTFSellOrder();

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrder_RevertIf_NotSellOrder() public {
        Order memory order = _createMockCTFSellOrder();
        order.side = Side.BUY;

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.expectRevert(IPredictDotLoan.NotSellOrder.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrder_RevertIf_InsufficientCollateral() public {
        Order memory order = _createMockCTFSellOrder();

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.loanAmount = order.takerAmount;
        proposal.signature = _signProposal(proposal);

        order.makerAmount = COLLATERAL_AMOUNT / 2;

        vm.expectRevert(IPredictDotLoan.InsufficientCollateral.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrder_RevertIf_OrderDidNotFill() public {
        Order memory order = _createMockCTFSellOrder();

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.loanAmount = order.takerAmount;
        proposal.signature = _signProposal(proposal);

        mockCTFExchange.setSimulateFailedOrderWithoutRevert(true);

        vm.expectRevert(IPredictDotLoan.OrderDidNotFill.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    /*//////////////////////////////////////////////////////////////
              TESTS BELOW ARE FOR _assertProposalValidity
    //////////////////////////////////////////////////////////////*/

    function test_acceptLoanOfferAndFillOrderRevertIf_QuestionResolved() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        vm.expectRevert(IPredictDotLoan.QuestionResolved.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_AbnormalQuestionState() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_NotLoanOffer() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        Order memory order = _createMockCTFSellOrder();
        proposal.loanAmount = order.takerAmount;
        proposal.signature = _signProposal(proposal);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.NotLoanOffer.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_CollateralizationRatioTooLow() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.collateralAmount = proposal.loanAmount - 1;
        proposal.signature = _signProposal(proposal);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.CollateralizationRatioTooLow.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_InvalidNonce() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        vm.prank(lender);
        predictDotLoan.incrementNonces(true, false);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.InvalidNonce.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_ProposalCancelled() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        _cancelLendingSalt(proposal.from, proposal.salt);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.ProposalCancelled.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_SaltAlreadyUsed() public {
        testFuzz_acceptLoanOfferAndFillOrder(0);

        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.loanAmount = LOAN_AMOUNT + 1;
        proposal.salt = 1;
        proposal.signature = _signProposal(proposal);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.SaltAlreadyUsed.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_RevertIf_InterestRatePerSecondTooLow(
        uint256 interestRatePerSecond
    ) public asPrankedUser(borrower) {
        vm.assume(interestRatePerSecond <= ONE);

        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.interestRatePerSecond = interestRatePerSecond;
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooLow.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_RevertIf_InterestRatePerSecondTooHigh(
        uint256 interestRatePerSecond
    ) public asPrankedUser(borrower) {
        vm.assume(interestRatePerSecond > ONE + TEN_THOUSAND_APY);

        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.interestRatePerSecond = interestRatePerSecond;
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooHigh.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_RevertIf_FulfillAmountTooHigh(
        uint256 extra
    ) public asPrankedUser(borrower) {
        vm.assume(extra > 0 && extra < 100_000_000 ether);

        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        order.takerAmount = proposal.loanAmount + extra;

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooHigh.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrder_PartialFulfillment() public asPrankedUser(borrower) {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.loanAmount = LOAN_AMOUNT;
        order.makerAmount = COLLATERAL_AMOUNT / 10;
        order.takerAmount = LOAN_AMOUNT / 10;
        proposal.signature = _signProposal(proposal);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        _assertLoanCreated_PartialFulfillmentFirstLeg();

        (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(proposal);
        assertEq(proposalId, predictDotLoan.hashProposal(proposal));
        assertEq(collateralAmount, order.makerAmount);
        assertEq(loanAmount, order.takerAmount);

        order.makerAmount = COLLATERAL_AMOUNT - order.makerAmount;
        order.takerAmount = LOAN_AMOUNT - order.takerAmount;

        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        _assertLoanCreated_PartialFulfillmentSecondLeg();

        _assertLoanOfferFulfillmentData(proposal);
    }

    function test_acceptLoanOfferAndFillOrder_RevertIf_FulfillAmountTooLow_Zero() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        order.takerAmount = 0;

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function testFuzz_acceptLoanOfferAndFillOrder_PartialFulfillment_RevertIf_FulfillAmountTooLow(
        uint256 amount
    ) public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        vm.assume(amount < proposal.loanAmount / 10);

        order.takerAmount = amount;

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrder_PartialFulfillment_RevertIf_FulfillAmountTooHigh()
        public
        asPrankedUser(borrower)
    {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.loanAmount = LOAN_AMOUNT;
        order.makerAmount = COLLATERAL_AMOUNT / 10;
        order.takerAmount = LOAN_AMOUNT / 10;
        proposal.signature = _signProposal(proposal);

        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        order.makerAmount = COLLATERAL_AMOUNT;
        order.takerAmount = LOAN_AMOUNT;

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooHigh.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_PositionIdMismatch() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.questionType = IPredictDotLoan.QuestionType.NegRisk;
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.PositionIdMismatch.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_PositionIdNotTradeableOnExchange() public {
        mockCTFExchange.deregisterToken(_getPositionId(true), _getPositionId(false));
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();

        vm.expectRevert(IPredictDotLoan.PositionIdNotTradeableOnExchange.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_InvalidSignature_SignerIsNotMaker() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.from = address(69);
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_InvalidSignature_ECDSAInvalidSignature() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.signature = new bytes(65);

        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function test_acceptLoanOfferAndFillOrderRevertIf_RevertIf_InvalidSignature_ECDSAInvalidSignatureLength() public {
        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.signature = new bytes(69);

        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    // // function test_acceptLoanOfferAndFillOrderRevertIf_InvalidSignature_InvalidSignatureS() public {}

    function testFuzz_acceptLoanOfferAndFillOrder_RevertIf_Expired(uint256 timestamp) public {
        vm.assume(timestamp > 0 && timestamp < 1721852833);

        (IPredictDotLoan.Proposal memory proposal, Order memory order) = _generateOrderAndProposal();
        proposal.validUntil = timestamp;
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.Expired.selector);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);
    }

    function _generateOrderAndProposal()
        private
        view
        returns (IPredictDotLoan.Proposal memory proposal, Order memory order)
    {
        proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        order = _createMockCTFSellOrder();
        proposal.loanAmount = order.takerAmount;
        proposal.signature = _signProposal(proposal);
    }
}
