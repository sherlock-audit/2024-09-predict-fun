// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";

import {PredictDotLoan_Test} from "./PredictDotLoan.t.sol";
import {MockEIP1271Wallet} from "../mock/MockEIP1271Wallet.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";

contract PredictDotLoan_AcceptBorrowRequest_Test is PredictDotLoan_Test {
    function test_acceptBorrowRequest_EIP1271() public {
        wallet = new MockEIP1271Wallet(borrower);
        vm.label(address(wallet), "Borrower's EIP-1271 Wallet");
        _mintCTF(address(wallet), COLLATERAL_AMOUNT);
        vm.prank(address(wallet));
        mockCTF.setApprovalForAll(address(predictDotLoan), true);
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.from = address(wallet);
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);
        _assertBalanceAndFulfillmentBeforeExecution(address(wallet), lender, proposal);
        _assertProposalAcceptedEmitted(predictDotLoan.hashProposal(proposal), address(wallet), lender);
        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
        assertEq(mockERC20.balanceOf(address(wallet)), proposal.loanAmount);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        (bytes32 proposalId, uint256 _collateralAmount, uint256 _loanAmount) = predictDotLoan.getFulfillment(proposal);
        assertEq(proposalId, predictDotLoan.hashProposal(proposal));
        assertEq(_collateralAmount, proposal.collateralAmount);
        assertEq(_loanAmount, proposal.loanAmount);
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
        assertEq(_borrower, address(wallet));
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
    }

    function test_acceptBorrowRequest_SameSaltCanBeUsedByAnotherBorrower() public {
        testFuzz_acceptBorrowRequest(0);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.salt = 1;
        proposal.from = borrower2;
        proposal.signature = _signProposal(proposal, borrower2PrivateKey);

        mockERC20.mint(lender, proposal.loanAmount);
        _mintCTF(borrower2, COLLATERAL_AMOUNT);

        vm.prank(lender);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        vm.prank(borrower2);
        mockCTF.setApprovalForAll(address(predictDotLoan), true);

        expectEmitCheckAll();
        emit ProposalAccepted(
            2,
            predictDotLoan.hashProposal(proposal),
            proposal.from,
            lender,
            _getPositionId(true),
            COLLATERAL_AMOUNT,
            LOAN_AMOUNT,
            0
        );

        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function testFuzz_acceptBorrowRequest_RevertIf_ProtocolFeeBasisPointsMismatch(uint8 protocolFeeBasisPoints) public {
        vm.assume(protocolFeeBasisPoints != _getProtocolFeeBasisPoints());

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.protocolFeeBasisPoints = protocolFeeBasisPoints;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        vm.prank(lender);
        vm.expectRevert(IPredictDotLoan.ProtocolFeeBasisPointsMismatch.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_LenderIsBorrower() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.LenderIsBorrower.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_AbnormalQuestionState() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        vm.prank(lender);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        vm.prank(lender);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        vm.prank(lender);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_NotBorrowRequest() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);
        vm.expectRevert(IPredictDotLoan.NotBorrowRequest.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_CollateralizationRatioTooLow() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.collateralAmount = LOAN_AMOUNT - 1;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        vm.prank(lender);
        vm.expectRevert(IPredictDotLoan.CollateralizationRatioTooLow.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_InvalidNonce() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrower);
        predictDotLoan.incrementNonces(false, true);

        vm.prank(lender);
        vm.expectRevert(IPredictDotLoan.InvalidNonce.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_ProposalCancelled() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        _cancelBorrowingSalt(proposal.salt);

        vm.prank(lender);
        vm.expectRevert(IPredictDotLoan.ProposalCancelled.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_SaltAlreadyUsed() public {
        testFuzz_acceptBorrowRequest(0);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.loanAmount = LOAN_AMOUNT + 1;
        proposal.salt = 1;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        vm.prank(lender);
        vm.expectRevert(IPredictDotLoan.SaltAlreadyUsed.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function testFuzz_acceptBorrowRequest_RevertIf_InterestRatePerSecondTooLow(
        uint256 interestRatePerSecond
    ) public asPrankedUser(lender) {
        vm.assume(interestRatePerSecond <= ONE);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = interestRatePerSecond;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooLow.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function testFuzz_acceptBorrowRequest_RevertIf_InterestRatePerSecondTooHigh(
        uint256 interestRatePerSecond
    ) public asPrankedUser(lender) {
        vm.assume(interestRatePerSecond > ONE + TEN_THOUSAND_APY);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = interestRatePerSecond;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooHigh.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function testFuzz_acceptBorrowRequest_RevertIf_FulfillAmountTooHigh(uint256 extra) public asPrankedUser(lender) {
        vm.assume(extra > 0 && extra < 100_000_000 ether);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooHigh.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount + extra);
    }

    function test_acceptBorrowRequest_PartialFulfillment() public asPrankedUser(lender) {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        uint256 fulfillAmount = proposal.loanAmount / 10;

        predictDotLoan.acceptBorrowRequest(proposal, fulfillAmount);

        _assertLoanCreated_PartialFulfillmentFirstLeg();

        (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) = predictDotLoan.getFulfillment(proposal);
        assertEq(proposalId, predictDotLoan.hashProposal(proposal));
        assertEq(collateralAmount, proposal.collateralAmount / 10);
        assertEq(loanAmount, fulfillAmount);

        predictDotLoan.acceptBorrowRequest(proposal, fulfillAmount * 9);

        _assertLoanCreated_PartialFulfillmentSecondLeg();

        _assertBorrowRequestFulfillmentData(proposal);
    }

    function testFuzz_acceptBorrowRequest_PartialFulfillment_FulfillAmountLowerThanTenPercentButFillTheProposal(
        uint256 amount
    ) public {
        vm.assume(amount > 0 && amount < LOAN_AMOUNT / 10);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        vm.startPrank(lender);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount - amount);
        predictDotLoan.acceptBorrowRequest(proposal, amount);
        vm.stopPrank();

        assertEq(mockERC20.balanceOf(borrower), proposal.loanAmount);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        _assertBorrowRequestFulfillmentData(proposal);
    }

    function testFuzz_acceptBorrowRequest_PartialFulfillment_LastBorrowerMaxPrecisionLossWithinRange(
        uint256 seed
    ) public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        uint256 fulfilledAmount;
        address currentLender = address(888);

        while (fulfilledAmount < LOAN_AMOUNT) {
            uint256 fulfillAmount = bound(seed, LOAN_AMOUNT / 10, (LOAN_AMOUNT * 11) / 100);
            seed = uint256(keccak256(abi.encodePacked(seed)));

            if (fulfillAmount > LOAN_AMOUNT - fulfilledAmount) {
                fulfillAmount = LOAN_AMOUNT - fulfilledAmount;

                uint256 collateralAmountRequiredWithoutPrecisionLoss = (fulfillAmount * COLLATERAL_AMOUNT) /
                    LOAN_AMOUNT;
                uint256 actualCollateralAmount = COLLATERAL_AMOUNT -
                    mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true));

                mockERC20.mint(currentLender, fulfillAmount);

                vm.startPrank(currentLender);
                mockERC20.approve(address(predictDotLoan), fulfillAmount);
                predictDotLoan.acceptBorrowRequest(proposal, fulfillAmount);
                vm.stopPrank();

                assertLe(
                    actualCollateralAmount - collateralAmountRequiredWithoutPrecisionLoss,
                    8 wei,
                    "The last borrower's required collateral should not be significantly higher"
                );

                currentLender = address(uint160(currentLender) + 1);
                fulfilledAmount += fulfillAmount;

                assertEq(mockERC20.balanceOf(borrower), fulfilledAmount);
            } else {
                mockERC20.mint(currentLender, fulfillAmount);

                vm.startPrank(currentLender);
                mockERC20.approve(address(predictDotLoan), fulfillAmount);
                predictDotLoan.acceptBorrowRequest(proposal, fulfillAmount);
                vm.stopPrank();

                currentLender = address(uint160(currentLender) + 1);
                fulfilledAmount += fulfillAmount;
            }
        }

        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        _assertBorrowRequestFulfillmentData(proposal);
    }

    function test_acceptBorrowRequest_RevertIf_FulfillAmountTooLow_Zero() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        predictDotLoan.acceptBorrowRequest(proposal, 0);
    }

    function testFuzz_acceptBorrowRequest_PartialFulfillment_RevertIf_FulfillAmountTooLow(uint256 amount) public {
        vm.assume(amount < LOAN_AMOUNT / 10);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        predictDotLoan.acceptBorrowRequest(proposal, amount);
    }

    function test_acceptBorrowRequest_PartialFulfillment_RevertIf_FulfillAmountTooHigh() public asPrankedUser(lender) {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount / 2);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooHigh.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_PositionIdNotTradeableOnExchange_NotRegistered() public {
        mockCTFExchange.deregisterToken(_getPositionId(true), _getPositionId(false));
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.expectRevert(IPredictDotLoan.PositionIdNotTradeableOnExchange.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_InvalidSignature_SignerIsNotMaker() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.from = address(69);
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_ECDSAInvalidSignature() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.signature = new bytes(65);

        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    function test_acceptBorrowRequest_RevertIf_InvalidSignature_ECDSAInvalidSignatureLength() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.signature = new bytes(69);

        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }

    // function test_acceptBorrowRequest_RevertIf_InvalidSignature_InvalidSignatureS() public {}

    function testFuzz_acceptBorrowRequest_RevertIf_Expired(uint256 timestamp) public {
        vm.assume(timestamp > 0 && timestamp < 1721852833);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        proposal.validUntil = timestamp;
        proposal.signature = _signProposal(proposal, borrowerPrivateKey);

        vm.expectRevert(IPredictDotLoan.Expired.selector);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);
    }
}
