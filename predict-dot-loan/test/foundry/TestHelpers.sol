// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {BlastPredictDotLoan} from "../../contracts/BlastPredictDotLoan.sol";
import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";
import {Order, Side, SignatureType} from "../../contracts/interfaces/ICTFExchange.sol";

import {AddressFinder} from "../mock/AddressFinder.sol";
import {MockBlastPoints} from "../mock/MockBlastPoints.sol";
import {MockBlastYield} from "../mock/MockBlastYield.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockEIP1271Wallet} from "../mock/MockEIP1271Wallet.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";
import {ConditionalTokens} from "../mock/ConditionalTokens/ConditionalTokens.sol";
import {CTHelpers} from "../mock/ConditionalTokens/CTHelpers.sol";
import {MockCTFExchange} from "../mock/CTFExchange/MockCTFExchange.sol";
import {MockNegRiskAdapter} from "../mock/NegRiskAdapter/MockNegRiskAdapter.sol";
import {MockNegRiskOperator} from "../mock/NegRiskAdapter/MockNegRiskOperator.sol";
import {MockNegRiskIdLib} from "../mock/NegRiskAdapter/MockNegRiskIdLib.sol";

import {AssertionHelpers} from "./AssertionHelpers.sol";

abstract contract TestHelpers is AssertionHelpers {
    modifier asPrankedUser(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    function _deploy() internal {
        mockBlastPoints = new MockBlastPoints();
        mockBlastYield = new MockBlastYield();

        mockCTF = new ConditionalTokens("https://predict.fun");

        mockERC20 = new MockERC20("USDB", "USDB");

        mockUmaCtfAdapter = new MockUmaCtfAdapter(address(mockCTF));
        mockNegRiskUmaCtfAdapter = new MockUmaCtfAdapter(address(mockCTF));
        mockNegRiskAdapter = new MockNegRiskAdapter(address(mockCTF), address(mockERC20));
        mockNegRiskOperator = new MockNegRiskOperator(address(mockNegRiskAdapter));

        mockNegRiskOperator.setQuestionId(negRiskQuestionId, MockNegRiskIdLib.getQuestionId(_getNegRiskMarketId(), 0));

        mockUmaCtfAdapter.prepareCondition(SINGLE_OUTCOME_QUESTION);
        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.PriceNotAvailable);

        mockNegRiskUmaCtfAdapter.prepareCondition(MULTI_OUTCOMES_QUESTION);
        mockNegRiskUmaCtfAdapter.setPayoutStatus(negRiskQuestionId, MockUmaCtfAdapter.PayoutStatus.PriceNotAvailable);

        mockCTFExchange = new MockCTFExchange(address(mockCTF), address(mockERC20));
        mockNegRiskCTFExchange = new MockCTFExchange(address(mockNegRiskAdapter), address(mockERC20));

        addressFinder = new AddressFinder();
        addressFinder.changeImplementationAddress("Blast", address(mockBlastYield));
        addressFinder.changeImplementationAddress("BlastPoints", address(mockBlastPoints));
        addressFinder.changeImplementationAddress("BlastPointsOperator", blastPointsOperator);
        addressFinder.changeImplementationAddress("Governor", owner);

        predictDotLoan = new BlastPredictDotLoan(
            protocolFeeRecipient,
            address(mockCTFExchange),
            address(mockNegRiskCTFExchange),
            address(mockUmaCtfAdapter),
            address(mockNegRiskUmaCtfAdapter),
            address(mockNegRiskOperator),
            address(addressFinder),
            owner
        );

        vm.startPrank(owner);

        mockCTFExchange.addOperator(address(predictDotLoan));
        mockNegRiskCTFExchange.addOperator(address(predictDotLoan));

        bytes32 conditionId = mockCTF.getConditionId(address(mockUmaCtfAdapter), questionId, 2);
        mockCTFExchange.registerToken(_getPositionId(true), _getPositionId(false), conditionId);

        bytes32 negRiskConditionId = mockNegRiskAdapter.getConditionId(negRiskQuestionId);
        mockNegRiskCTFExchange.registerToken(
            mockNegRiskAdapter.getPositionId(negRiskQuestionId, true),
            mockNegRiskAdapter.getPositionId(negRiskQuestionId, false),
            negRiskConditionId
        );

        predictDotLoan.grantRole(keccak256("REFINANCIER_ROLE"), bot);
        predictDotLoan.grantRole(keccak256("PROPOSALS_MATCHER_ROLE"), bot);

        mockNegRiskAdapter.addAdmin(address(mockNegRiskCTFExchange));

        predictDotLoan.updateMinimumOrderFeeRate(0);

        vm.stopPrank();

        vm.label(address(predictDotLoan), "Lending Contract");
        vm.label(address(mockERC20), "USDB");
        vm.label(address(mockCTF), "CTF");
        vm.label(lender, "Lender 1");
        vm.label(lender2, "Lender 2");
        vm.label(borrower, "Borrower");
    }

    function _mintCTF(address to, uint256 collateralAmount) internal {
        mockERC20.mint(to, collateralAmount);

        bytes32 conditionId = CTHelpers.getConditionId(address(mockUmaCtfAdapter), questionId, 2);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        vm.startPrank(to);
        mockERC20.approve(address(mockCTF), collateralAmount);
        mockCTF.splitPosition(IERC20(address(mockERC20)), bytes32(0), conditionId, partition, collateralAmount);
        vm.stopPrank();
    }

    function _mintNegRiskCTF(address to, uint256 collateralAmount) internal {
        mockERC20.mint(to, collateralAmount);

        bytes32 conditionId = mockNegRiskAdapter.getConditionId(negRiskQuestionId);

        mockNegRiskAdapter.prepareCondition(negRiskQuestionId);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        vm.startPrank(to);
        mockERC20.approve(address(mockNegRiskAdapter), collateralAmount);
        mockNegRiskAdapter.splitPosition(address(mockERC20), bytes32(0), conditionId, partition, collateralAmount);
        vm.stopPrank();
    }

    function _generateBaseProposal(
        IPredictDotLoan.QuestionType questionType
    ) internal view returns (IPredictDotLoan.Proposal memory proposal) {
        proposal.loanAmount = LOAN_AMOUNT;
        proposal.collateralAmount = COLLATERAL_AMOUNT;
        proposal.duration = LOAN_DURATION;
        proposal.validUntil = vm.getBlockTimestamp() + 1 days;

        if (questionType == IPredictDotLoan.QuestionType.Binary) {
            proposal.questionId = questionId;
        } else if (questionType == IPredictDotLoan.QuestionType.NegRisk) {
            proposal.questionId = negRiskQuestionId;
        }
        proposal.questionType = questionType;
        proposal.outcome = true;
        proposal.interestRatePerSecond = INTEREST_RATE_PER_SECOND;
        proposal.salt = uint256(vm.load(address(predictDotLoan), bytes32(uint256(8))));
        proposal.protocolFeeBasisPoints = _getProtocolFeeBasisPoints();
    }

    function _generateLoanOffer(
        IPredictDotLoan.QuestionType questionType
    ) internal view returns (IPredictDotLoan.Proposal memory proposal) {
        proposal = _generateBaseProposal(questionType);
        proposal.from = lender;
        proposal.proposalType = IPredictDotLoan.ProposalType.LoanOffer;

        (uint128 lendingNonce, ) = predictDotLoan.nonces(lender);
        proposal.nonce = lendingNonce;

        proposal.signature = _signProposal(proposal);
    }

    function _generateBorrowRequest(
        IPredictDotLoan.QuestionType questionType
    ) internal view returns (IPredictDotLoan.Proposal memory proposal) {
        proposal = _generateBaseProposal(questionType);
        proposal.from = borrower;
        proposal.proposalType = IPredictDotLoan.ProposalType.BorrowRequest;

        (, uint128 borrowingNonce) = predictDotLoan.nonces(lender);
        proposal.nonce = borrowingNonce;

        proposal.signature = _signProposal(proposal, borrowerPrivateKey);
    }

    function _signProposal(IPredictDotLoan.Proposal memory proposal) internal view returns (bytes memory signature) {
        signature = _signProposal(proposal, lenderPrivateKey);
    }

    function _signProposal(
        IPredictDotLoan.Proposal memory proposal,
        uint256 privateKey
    ) internal view returns (bytes memory signature) {
        bytes32 digest = predictDotLoan.hashProposal(proposal);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _cancelLendingSalt(address user, uint256 salt) internal {
        IPredictDotLoan.SaltCancellationRequest[] memory requests = new IPredictDotLoan.SaltCancellationRequest[](1);
        requests[0].salt = salt;
        requests[0].lending = true;

        vm.prank(user);
        predictDotLoan.cancel(requests);
    }

    function _cancelBorrowingSalt(uint256 salt) internal {
        IPredictDotLoan.SaltCancellationRequest[] memory requests = new IPredictDotLoan.SaltCancellationRequest[](1);
        requests[0].salt = salt;
        requests[0].borrowing = true;

        vm.prank(borrower);
        predictDotLoan.cancel(requests);
    }

    function _getLoanStatus(uint256 loanId) internal view returns (IPredictDotLoan.LoanStatus) {
        (, , , , , , , , , IPredictDotLoan.LoanStatus status, ) = predictDotLoan.loans(loanId);
        return status;
    }

    function _updateProtocolFeeRecipientAndBasisPoints(uint8 protocolFeeBasisPoints) internal {
        vm.assume(protocolFeeBasisPoints <= 200);

        vm.startPrank(owner);
        predictDotLoan.updateProtocolFeeRecipient(protocolFeeRecipient);
        predictDotLoan.updateProtocolFeeBasisPoints(protocolFeeBasisPoints);
        vm.stopPrank();
    }

    function _generateLoanOfferForRefinancing_SameCollateralAmount(
        IPredictDotLoan.QuestionType questionType
    ) internal view returns (IPredictDotLoan.Proposal memory proposal) {
        proposal = _generateLoanOffer(questionType);
        proposal.from = lender2;
        proposal.interestRatePerSecond = INTEREST_RATE_PER_SECOND - 1;
        uint256 debt = predictDotLoan.calculateDebt(1);
        uint256 protocolFeeBasisPoints = _getProtocolFeeBasisPoints();
        proposal.loanAmount = debt + (debt * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints);
        uint256 expectedDebt = 700.091338682534955100 ether;
        assertEq(
            proposal.loanAmount,
            expectedDebt + (expectedDebt * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints)
        );
        proposal.duration = LOAN_DURATION * 2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);
    }

    function _generateLoanOfferForRefinancing_BetterCollateralRatio(
        IPredictDotLoan.QuestionType questionType
    ) internal view returns (IPredictDotLoan.Proposal memory proposal) {
        proposal = _generateLoanOffer(questionType);
        proposal.from = lender2;
        proposal.interestRatePerSecond = INTEREST_RATE_PER_SECOND - 1;
        proposal.loanAmount =
            predictDotLoan.calculateDebt(1) +
            (predictDotLoan.calculateDebt(1) * _getProtocolFeeBasisPoints()) /
            (10_000 - _getProtocolFeeBasisPoints()) +
            100 ether;
        proposal.duration = LOAN_DURATION * 2;
        proposal.signature = _signProposal(proposal, lender2PrivateKey);
    }

    function _createOrder(
        address maker,
        uint256 tokenId,
        uint256 makerAmount,
        uint256 takerAmount,
        Side side
    ) internal pure returns (Order memory) {
        Order memory order = Order({
            salt: 1,
            signer: maker,
            maker: maker,
            taker: address(0),
            tokenId: tokenId,
            makerAmount: makerAmount,
            takerAmount: takerAmount,
            expiration: 0,
            nonce: 0,
            feeRateBps: 0,
            signatureType: SignatureType.EOA,
            side: side,
            signature: new bytes(0)
        });
        return order;
    }

    // mock CTF exchange does not check signature
    function _createMockCTFSellOrder() internal view returns (Order memory order) {
        order = _createOrder(
            whiteKnight,
            _getPositionId(true),
            COLLATERAL_AMOUNT,
            COLLATERAL_AMOUNT / 2, // 50c
            Side.SELL
        );
    }

    function _mintTokensAndApproveForSetup(uint256 loanAmount, uint256 collateralAmount) internal {
        mockERC20.mint(lender, loanAmount);
        vm.prank(lender);
        mockERC20.approve(address(predictDotLoan), loanAmount);
        vm.prank(borrower);
        mockCTF.setApprovalForAll(address(predictDotLoan), true);
        _mintCTF(borrower, collateralAmount);
        _mintNegRiskCTF(borrower, collateralAmount);
    }

    function _getNegRiskMarketId() internal view returns (bytes32 marketId) {
        marketId = MockNegRiskIdLib.getMarketId(address(mockNegRiskOperator), 0, MULTI_OUTCOMES_MARKET);
    }
}
