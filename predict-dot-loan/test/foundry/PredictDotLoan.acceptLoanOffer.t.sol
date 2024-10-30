// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";

import {PredictDotLoan_Test} from "./PredictDotLoan.t.sol";
import {MockEIP1271Wallet} from "../mock/MockEIP1271Wallet.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";

contract PredictDotLoan_AcceptLoanOffer_Test is PredictDotLoan_Test {
    function test_acceptLoanOffer_EIP1271() public {
        wallet = new MockEIP1271Wallet(lender);
        vm.label(address(wallet), "Lender's EIP-1271 Wallet");
        mockERC20.mint(address(wallet), LOAN_AMOUNT);
        vm.prank(address(wallet));
        mockERC20.approve(address(predictDotLoan), LOAN_AMOUNT);
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = address(wallet);
        proposal.signature = _signProposal(proposal);
        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);
        _assertProposalAcceptedEmitted(predictDotLoan.hashProposal(proposal), borrower, address(wallet));
        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
        assertEq(mockERC20.balanceOf(borrower), proposal.loanAmount);
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
        assertEq(_borrower, borrower);
        assertEq(_lender, address(wallet));
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

    function test_acceptLoanOffer_SameSaltCanBeUsedByAnotherLender() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.salt = 1;
        proposal.from = lender2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);

        mockERC20.mint(proposal.from, proposal.loanAmount);
        _mintCTF(borrower, COLLATERAL_AMOUNT);

        vm.prank(proposal.from);
        mockERC20.approve(address(predictDotLoan), proposal.loanAmount);

        expectEmitCheckAll();
        emit ProposalAccepted(
            2,
            predictDotLoan.hashProposal(proposal),
            borrower,
            proposal.from,
            _getPositionId(true),
            COLLATERAL_AMOUNT,
            LOAN_AMOUNT,
            0
        );

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function testFuzz_acceptLoanOffer_RevertIf_ProtocolFeeBasisPointsMismatch(uint8 protocolFeeBasisPoints) public {
        vm.assume(protocolFeeBasisPoints != _getProtocolFeeBasisPoints());

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.protocolFeeBasisPoints = protocolFeeBasisPoints;
        proposal.signature = _signProposal(proposal);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.ProtocolFeeBasisPointsMismatch.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_LenderIsBorrower() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);
        vm.expectRevert(IPredictDotLoan.LenderIsBorrower.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_QuestionResolved() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.HasPrice);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.QuestionResolved.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_AbnormalQuestionState() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Flagged);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.NotInitialized);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);

        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.Paused);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.AbnormalQuestionState.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_NotLoanOffer() public {
        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.NotLoanOffer.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_CollateralizationRatioTooLow() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.collateralAmount = LOAN_AMOUNT - 1;
        proposal.signature = _signProposal(proposal);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.CollateralizationRatioTooLow.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_InvalidNonce() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(lender);
        predictDotLoan.incrementNonces(true, false);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.InvalidNonce.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_ProposalCancelled() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        _cancelLendingSalt(proposal.from, proposal.salt);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.ProposalCancelled.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_SaltAlreadyUsed() public {
        testFuzz_acceptLoanOffer(0);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.loanAmount = LOAN_AMOUNT + 1;
        proposal.salt = 1;
        proposal.signature = _signProposal(proposal);

        vm.prank(borrower);
        vm.expectRevert(IPredictDotLoan.SaltAlreadyUsed.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function testFuzz_acceptLoanOffer_RevertIf_InterestRatePerSecondTooLow(
        uint256 interestRatePerSecond
    ) public asPrankedUser(borrower) {
        vm.assume(interestRatePerSecond <= ONE);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = interestRatePerSecond;
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooLow.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function testFuzz_acceptLoanOffer_RevertIf_InterestRatePerSecondTooHigh(
        uint256 interestRatePerSecond
    ) public asPrankedUser(borrower) {
        vm.assume(interestRatePerSecond > ONE + TEN_THOUSAND_APY);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.interestRatePerSecond = interestRatePerSecond;
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InterestRatePerSecondTooHigh.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function testFuzz_acceptLoanOffer_RevertIf_FulfillAmountTooHigh(uint256 extra) public asPrankedUser(borrower) {
        vm.assume(extra > 0 && extra < 100_000_000 ether);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooHigh.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount + extra);
    }

    function test_acceptLoanOffer_PartialFulfillment() public asPrankedUser(borrower) {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        uint256 fulfillAmount = LOAN_AMOUNT / 10;

        predictDotLoan.acceptLoanOffer(proposal, fulfillAmount);

        _assertLoanCreated_PartialFulfillmentFirstLeg();

        (bytes32 proposalId, uint256 _collateralAmount, uint256 _loanAmount) = predictDotLoan.getFulfillment(proposal);
        assertEq(proposalId, predictDotLoan.hashProposal(proposal));
        assertEq(_collateralAmount, proposal.collateralAmount / 10);
        assertEq(_loanAmount, fulfillAmount);

        predictDotLoan.acceptLoanOffer(proposal, fulfillAmount * 9);

        _assertLoanCreated_PartialFulfillmentSecondLeg();

        _assertLoanOfferFulfillmentData(proposal);
    }

    function testFuzz_acceptLoanOffer_PartialFulfillment_FulfillAmountLowerThanTenPercentButFillTheProposal(
        uint256 amount
    ) public {
        vm.assume(amount > 0 && amount < LOAN_AMOUNT / 10);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        vm.startPrank(borrower);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount - amount);
        predictDotLoan.acceptLoanOffer(proposal, amount);
        vm.stopPrank();

        assertEq(mockERC20.balanceOf(borrower), proposal.loanAmount);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        _assertLoanOfferFulfillmentData(proposal);
    }

    function testFuzz_acceptLoanOffer_PartialFulfillment_LastBorrowerMaxPrecisionLossWithinRange(uint256 seed) public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        uint256 fulfilledAmount;
        address currentBorrower = address(888);

        while (fulfilledAmount < LOAN_AMOUNT) {
            _mintCTF(currentBorrower, COLLATERAL_AMOUNT);

            uint256 fulfillAmount = bound(seed, LOAN_AMOUNT / 10, (LOAN_AMOUNT * 11) / 100);
            seed = uint256(keccak256(abi.encodePacked(seed)));

            if (fulfillAmount > LOAN_AMOUNT - fulfilledAmount) {
                fulfillAmount = LOAN_AMOUNT - fulfilledAmount;

                vm.startPrank(currentBorrower);
                mockCTF.setApprovalForAll(address(predictDotLoan), true);
                predictDotLoan.acceptLoanOffer(proposal, fulfillAmount);
                vm.stopPrank();

                uint256 collateralAmountRequiredWithoutPrecisionLoss = (fulfillAmount * COLLATERAL_AMOUNT) /
                    LOAN_AMOUNT;
                uint256 actualCollateralAmount = COLLATERAL_AMOUNT -
                    mockCTF.balanceOf(currentBorrower, _getPositionId(true));

                assertLe(
                    actualCollateralAmount - collateralAmountRequiredWithoutPrecisionLoss,
                    8 wei,
                    "The last borrower's required collateral should not be significantly higher"
                );

                assertEq(mockERC20.balanceOf(currentBorrower), fulfillAmount);

                currentBorrower = address(uint160(currentBorrower) + 1);
                fulfilledAmount += fulfillAmount;
            } else {
                vm.startPrank(currentBorrower);
                mockCTF.setApprovalForAll(address(predictDotLoan), true);
                predictDotLoan.acceptLoanOffer(proposal, fulfillAmount);
                vm.stopPrank();

                currentBorrower = address(uint160(currentBorrower) + 1);
                fulfilledAmount += fulfillAmount;
            }
        }

        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        _assertLoanOfferFulfillmentData(proposal);
    }

    function testacceptLoanOffer_RevertIf_FulfillAmountTooLow_Zero() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        predictDotLoan.acceptLoanOffer(proposal, 0);
    }

    function testFuzz_acceptLoanOffer_PartialFulfillment_RevertIf_FulfillAmountTooLow(uint256 amount) public {
        vm.assume(amount < LOAN_AMOUNT / 10);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooLow.selector);
        predictDotLoan.acceptLoanOffer(proposal, amount);
    }

    function test_acceptLoanOffer_PartialFulfillment_RevertIf_FulfillAmountTooHigh() public asPrankedUser(borrower) {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount / 2);

        vm.expectRevert(IPredictDotLoan.FulfillAmountTooHigh.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_PositionIdNotTradeableOnExchange_NotRegistered() public {
        mockCTFExchange.deregisterToken(_getPositionId(true), _getPositionId(false));
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        vm.expectRevert(IPredictDotLoan.PositionIdNotTradeableOnExchange.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_InvalidSignature_SignerIsNotMaker() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.from = address(69);
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_InvalidSignature_ECDSAInvalidSignature() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.signature = new bytes(65);

        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    function test_acceptLoanOffer_RevertIf_RevertIf_InvalidSignature_ECDSAInvalidSignatureLength() public {
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.signature = new bytes(69);

        vm.expectRevert(IPredictDotLoan.InvalidSignature.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }

    // function test_acceptLoanOffer_RevertIf_InvalidSignature_InvalidSignatureS() public {}

    function testFuzz_acceptLoanOffer_RevertIf_Expired(uint256 timestamp) public {
        vm.assume(timestamp > 0 && timestamp < 1721852833);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        proposal.validUntil = timestamp;
        proposal.signature = _signProposal(proposal);

        vm.expectRevert(IPredictDotLoan.Expired.selector);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);
    }
}
