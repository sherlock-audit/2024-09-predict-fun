// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {console2} from "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BlastPredictDotLoan} from "../../contracts/BlastPredictDotLoan.sol";
import {Order, Side, SignatureType} from "../../contracts/interfaces/ICTFExchange.sol";
import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";

import {InvariantTestHelpers} from "./InvariantTestHelpers.sol";

import {AddressFinder} from "../mock/AddressFinder.sol";
import {MockERC20} from "../mock/MockERC20.sol";
import {MockBlastSwissKnife} from "../mock/MockBlastSwissKnife.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";
import {ConditionalTokens} from "../mock/ConditionalTokens/ConditionalTokens.sol";
import {CTHelpers} from "../mock/ConditionalTokens/CTHelpers.sol";
import {MockCTFExchange} from "../mock/CTFExchange/MockCTFExchange.sol";
import {MockNegRiskAdapter} from "../mock/NegRiskAdapter/MockNegRiskAdapter.sol";
import {MockNegRiskOperator} from "../mock/NegRiskAdapter/MockNegRiskOperator.sol";
import {MockNegRiskIdLib} from "../mock/NegRiskAdapter/MockNegRiskIdLib.sol";

import {TestHelpers} from "./TestHelpers.sol";

contract Handler is InvariantTestHelpers {
    uint256 internal constant TEN_THOUSAND_APY = 146_247_483_013;

    bytes internal constant SINGLE_OUTCOME_QUESTION = "Adam Cochran for President 2024";
    bytes32 internal questionId = keccak256(SINGLE_OUTCOME_QUESTION);

    bytes internal constant MULTI_OUTCOMES_QUESTION = "Will Adam Cochran become the president in 2024?";
    bytes32 internal negRiskQuestionId = keccak256(MULTI_OUTCOMES_QUESTION);

    BlastPredictDotLoan public predictDotLoan;
    ConditionalTokens public mockCTF;
    MockERC20 public mockERC20;

    MockNegRiskAdapter public mockNegRiskAdapter;

    MockUmaCtfAdapter public mockUmaCtfAdapter;
    MockUmaCtfAdapter public mockNegRiskUmaCtfAdapter;

    address public owner;
    address public protocolFeeRecipient;

    uint256 public ghost_CTF_binaryYes_depositedSum;
    uint256 public ghost_CTF_binaryYes_withdrawnSum;

    uint256 public ghost_CTF_binaryNo_depositedSum;
    uint256 public ghost_CTF_binaryNo_withdrawnSum;

    uint256 public ghost_CTF_negRiskYes_depositedSum;
    uint256 public ghost_CTF_negRiskYes_withdrawnSum;

    uint256 public ghost_CTF_negRiskNo_depositedSum;
    uint256 public ghost_CTF_negRiskNo_withdrawnSum;

    enum CollateralTokenType {
        BinaryYes,
        BinaryNo,
        NegRiskYes,
        NegRiskNo
    }

    mapping(uint256 loanId => CollateralTokenType) collateralTokenType;

    mapping(address account => mapping(uint256 positionId => uint256 balance)) public accountPositionBalances;

    uint256 public globalSaltCounter;

    mapping(uint256 salt => address[] users) public salts;

    IPredictDotLoan.Proposal[] public borrowRequests;
    IPredictDotLoan.Proposal[] public loanOffers;

    constructor(
        address _owner,
        BlastPredictDotLoan _predictDotLoan,
        ConditionalTokens _mockCTF,
        MockERC20 _mockERC20,
        MockUmaCtfAdapter _mockUmaCtfAdapter,
        MockUmaCtfAdapter _mockNegRiskUmaCtfAdapter,
        MockNegRiskAdapter _mockNegRiskAdapter
    ) {
        owner = _owner;
        predictDotLoan = _predictDotLoan;
        mockCTF = _mockCTF;
        mockERC20 = _mockERC20;
        mockUmaCtfAdapter = _mockUmaCtfAdapter;
        mockNegRiskUmaCtfAdapter = _mockNegRiskUmaCtfAdapter;
        mockNegRiskAdapter = _mockNegRiskAdapter;
    }

    function callSummary() external view {
        console2.log("Call summary:");
        console2.log("-------------------");
        console2.log("Accept loan offer (sign)", calls["acceptLoanOffer_Sign"]);
        console2.log("Accept loan offer", calls["acceptLoanOffer"]);
        console2.log("Accept loan offer and fill order", calls["acceptLoanOfferAndFillOrder"]);
        console2.log("Accept borrow request (sign)", calls["acceptBorrowRequest_Sign"]);
        console2.log("Accept borrow request", calls["acceptBorrowRequest"]);
        console2.log("Match proposals", calls["matchProposals"]);
        console2.log("Repay", calls["repay"]);
        console2.log("Refinance", calls["refinance"]);
        console2.log("Call", calls["call"]);
        console2.log("Auction", calls["auction"]);
        console2.log("Seize", calls["seize"]);
        console2.log("Cancel", calls["cancel"]);
        console2.log("Increment nonces", calls["incrementNonces"]);
        console2.log("Update protocol fee basis points", calls["updateProtocolFeeBasisPoints"]);
        console2.log("Toggle auto refinancing enabled", calls["toggleAutoRefinancingEnabled"]);
        console2.log("Update minimum order fee rate", calls["updateMinimumOrderFeeRate"]);
        console2.log("-------------------");

        console2.log("Token flow summary:");
        console2.log("-------------------");
        console2.log("CTF Binary YES deposited:", ghost_CTF_binaryYes_depositedSum);
        console2.log("CTF Binary YES withdrawn:", ghost_CTF_binaryYes_withdrawnSum);
        console2.log("CTF Binary NO deposited:", ghost_CTF_binaryNo_depositedSum);
        console2.log("CTF Binary NO withdrawn:", ghost_CTF_binaryNo_withdrawnSum);
        console2.log("CTF Neg Risk YES deposited:", ghost_CTF_negRiskYes_depositedSum);
        console2.log("CTF Neg Risk YES withdrawn:", ghost_CTF_negRiskYes_withdrawnSum);
        console2.log("CTF Neg Risk NO deposited:", ghost_CTF_negRiskNo_depositedSum);
        console2.log("CTF Neg Risk NO withdrawn:", ghost_CTF_negRiskNo_withdrawnSum);
        console2.log("-------------------");
    }

    function acceptLoanOffer_Sign(uint256 seed) public countCall("acceptLoanOffer_Sign") {
        uint256 privateKey = bound(seed, 1, 100);
        address lender = vm.addr(privateKey);

        uint256 collateralAmount = bound(seed, 0.0002 ether, 100_000 ether);
        uint256 loanAmount = bound(seed, 0.0001 ether, collateralAmount);
        uint256 interestRatePerSecond = _chooseInterestRatePerSecond(seed);
        IPredictDotLoan.QuestionType questionType = _chooseQuestionType(seed);
        bool outcome = _chooseOutcome(seed);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(
            privateKey,
            collateralAmount,
            loanAmount,
            interestRatePerSecond,
            questionType,
            outcome
        );

        mockERC20.mint(lender, loanAmount);

        vm.prank(lender);
        mockERC20.approve(address(predictDotLoan), type(uint256).max);

        loanOffers.push(proposal);
    }

    function acceptLoanOffer(uint256 seed) public countCall("acceptLoanOffer") {
        address borrower = vm.addr(bound(seed, 1, 100));

        if (loanOffers.length > 0) {
            IPredictDotLoan.Proposal memory proposal = loanOffers[0];
            loanOffers[0] = loanOffers[loanOffers.length - 1];
            loanOffers.pop();

            if (vm.getBlockTimestamp() > proposal.validUntil) return;

            if (proposal.protocolFeeBasisPoints != _getProtocolFeeBasisPoints()) return;

            (bool lending, ) = predictDotLoan.saltCancellations(proposal.from, proposal.salt);

            if (lending) return;

            (uint128 lendingNonce, ) = predictDotLoan.nonces(proposal.from);
            if (proposal.nonce < lendingNonce) return;

            uint256 fulfillAmount = _chooseFulfillAmount(seed, proposal);

            uint256 collateralAmountRequired = predictDotLoan.calculateCollateralAmountRequired(
                proposal,
                fulfillAmount
            );

            if (borrower == proposal.from) {
                borrower = vm.addr(bound(seed, 1, 100) + 1);
            }

            if (proposal.questionType == IPredictDotLoan.QuestionType.Binary) {
                _mintCTF(borrower, collateralAmountRequired);
            } else {
                _mintNegRiskCTF(borrower, collateralAmountRequired);
            }

            _trackCurrentContractPositionBalance(proposal.questionType, proposal.outcome);

            vm.startPrank(borrower);
            mockCTF.setApprovalForAll(address(predictDotLoan), true);
            predictDotLoan.acceptLoanOffer(proposal, fulfillAmount);
            vm.stopPrank();

            _trackCollateralDeposited(
                proposal.questionType,
                proposal.outcome,
                _trackContractPositionBalanceChange(proposal.questionType, proposal.outcome)
            );

            // Loan offer is not fully fulfilled, so it should be added back to the loan offers
            (, , uint256 loanAmount) = predictDotLoan.getFulfillment(proposal);
            if (loanAmount < proposal.loanAmount) {
                loanOffers.push(proposal);
            }
        }
    }

    function acceptLoanOfferAndFillOrder(uint256 seed) public countCall("acceptLoanOfferAndFillOrder") {
        uint256 privateKey = bound(seed, 1, 100);
        address lender = vm.addr(privateKey);

        uint256 makerAmount = bound(seed, 0.0002 ether, 100_000 ether);
        uint256 takerAmount = bound(seed, 0.0001 ether, makerAmount);

        // This is just to make sure collateralization ratio is at least 100% as makerAmount can be equal to takerAmount
        // and the takerAmount will be multiplied by 1 + protocol fee basis points
        makerAmount =
            makerAmount +
            ((makerAmount * _getProtocolFeeBasisPoints()) / (10_000 - _getProtocolFeeBasisPoints()));

        IPredictDotLoan.QuestionType questionType = _chooseQuestionType(seed);
        bool outcome = _chooseOutcome(seed);

        address seller = address(69_420);
        Order memory order = Order({
            salt: 1,
            signer: seller,
            maker: seller,
            taker: address(0),
            tokenId: _derivePositionId(questionType, outcome),
            makerAmount: makerAmount,
            takerAmount: takerAmount,
            expiration: 0,
            nonce: 0,
            feeRateBps: _getMinimumOrderFeeRate(),
            signatureType: SignatureType.EOA,
            side: Side.SELL,
            signature: new bytes(0)
        });

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(
            privateKey,
            order.makerAmount,
            order.takerAmount +
                ((order.takerAmount * _getProtocolFeeBasisPoints()) / (10_000 - _getProtocolFeeBasisPoints())),
            _chooseInterestRatePerSecond(seed),
            questionType,
            outcome
        );

        // Partial fulfillment
        order.makerAmount = order.makerAmount / ((seed % 9) + 1);
        order.takerAmount = order.takerAmount / ((seed % 9) + 1);

        mockERC20.mint(lender, proposal.loanAmount);

        vm.prank(lender);
        mockERC20.approve(address(predictDotLoan), type(uint256).max);

        if (proposal.questionType == IPredictDotLoan.QuestionType.Binary) {
            _mintCTF(seller, order.makerAmount);
        } else {
            _mintNegRiskCTF(seller, order.makerAmount);
        }

        vm.startPrank(seller);
        mockCTF.setApprovalForAll(address(predictDotLoan.CTF_EXCHANGE()), true);
        mockCTF.setApprovalForAll(address(mockNegRiskAdapter), true);
        mockCTF.setApprovalForAll(address(predictDotLoan.NEG_RISK_CTF_EXCHANGE()), true);
        vm.stopPrank();

        _trackCurrentContractPositionBalance(proposal.questionType, proposal.outcome);

        address borrower = vm.addr(bound(seed, 1, 100) + 1);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOfferAndFillOrder(order, proposal);

        _trackCollateralDeposited(
            proposal.questionType,
            proposal.outcome,
            _trackContractPositionBalanceChange(proposal.questionType, proposal.outcome)
        );
    }

    function acceptBorrowRequest_Sign(uint256 seed) public countCall("acceptBorrowRequest_Sign") {
        uint256 privateKey = bound(seed, 1, 100);
        address borrower = vm.addr(privateKey);

        uint256 collateralAmount = bound(seed, 0.0002 ether, 100_000 ether);
        uint256 loanAmount = bound(seed, 0.0001 ether, collateralAmount);
        uint256 interestRatePerSecond = _chooseInterestRatePerSecond(seed);
        IPredictDotLoan.QuestionType questionType = _chooseQuestionType(seed);
        bool outcome = _chooseOutcome(seed);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(
            privateKey,
            collateralAmount,
            loanAmount,
            interestRatePerSecond,
            questionType,
            outcome
        );
        borrowRequests.push(proposal);

        if (questionType == IPredictDotLoan.QuestionType.Binary) {
            _mintCTF(borrower, collateralAmount);
        } else {
            _mintNegRiskCTF(borrower, collateralAmount);
        }
    }

    function acceptBorrowRequest(uint256 seed) public countCall("acceptBorrowRequest") {
        address lender = vm.addr(bound(seed, 1, 100));

        if (borrowRequests.length > 0) {
            IPredictDotLoan.Proposal memory proposal = borrowRequests[0];
            borrowRequests[0] = borrowRequests[borrowRequests.length - 1];
            borrowRequests.pop();

            if (vm.getBlockTimestamp() > proposal.validUntil) {
                return;
            }

            if (proposal.protocolFeeBasisPoints != _getProtocolFeeBasisPoints()) return;

            (, bool borrowing) = predictDotLoan.saltCancellations(proposal.from, proposal.salt);

            if (borrowing) return;

            (, uint128 borrowingNonce) = predictDotLoan.nonces(proposal.from);
            if (proposal.nonce < borrowingNonce) return;

            uint256 fulfillAmount = _chooseFulfillAmount(seed, proposal);

            uint256 collateralAmountRequired = predictDotLoan.calculateCollateralAmountRequired(
                proposal,
                fulfillAmount
            );

            if (proposal.questionType == IPredictDotLoan.QuestionType.Binary) {
                _mintCTF(proposal.from, collateralAmountRequired);
            } else {
                _mintNegRiskCTF(proposal.from, collateralAmountRequired);
            }

            _trackCurrentContractPositionBalance(proposal.questionType, proposal.outcome);

            if (lender == proposal.from) {
                lender = vm.addr(bound(seed, 1, 100) + 1);
            }

            mockERC20.mint(lender, fulfillAmount);

            vm.startPrank(lender);
            mockERC20.approve(address(predictDotLoan), type(uint256).max);
            predictDotLoan.acceptBorrowRequest(proposal, fulfillAmount);
            vm.stopPrank();

            _trackCollateralDeposited(
                proposal.questionType,
                proposal.outcome,
                _trackContractPositionBalanceChange(proposal.questionType, proposal.outcome)
            );

            // Loan offer is not fully fulfilled, so it should be added back to the loan offers
            (, , uint256 loanAmount) = predictDotLoan.getFulfillment(proposal);
            if (loanAmount < proposal.loanAmount) {
                borrowRequests.push(proposal);
            }
        }
    }

    function matchProposals(uint256 seed) public {
        uint256 lenderPrivateKey = bound(seed, 1, 100);
        address lender = vm.addr(lenderPrivateKey);

        uint256 collateralAmount = bound(seed, 0.0002 ether, 100_000 ether);
        uint256 loanAmount = bound(seed, 0.0001 ether, collateralAmount);
        uint256 interestRatePerSecond = _chooseInterestRatePerSecond(seed);
        IPredictDotLoan.QuestionType questionType = _chooseQuestionType(seed);
        bool outcome = _chooseOutcome(seed);

        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(
            lenderPrivateKey,
            collateralAmount,
            loanAmount,
            interestRatePerSecond,
            questionType,
            outcome
        );

        vm.prank(lender);
        mockERC20.approve(address(predictDotLoan), type(uint256).max);

        uint256 borrowerPrivateKey = bound(uint256(keccak256(abi.encode(seed))), 101, 200);
        address borrower = vm.addr(borrowerPrivateKey);

        seed = uint256(keccak256(abi.encode(seed)));
        if (seed % 2 == 0) {
            loanAmount = bound(seed, loanAmount / 10, loanAmount);
        } else {
            loanAmount = bound(seed, loanAmount, loanAmount * 10);
        }
        collateralAmount = (loanAmount * loanOffer.collateralAmount) / loanOffer.loanAmount;
        collateralAmount += (seed % collateralAmount);

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(
            borrowerPrivateKey,
            collateralAmount,
            loanAmount,
            interestRatePerSecond,
            questionType,
            outcome
        );

        borrowRequest.interestRatePerSecond = bound(
            seed,
            loanOffer.interestRatePerSecond,
            (1 ether + TEN_THOUSAND_APY + 1)
        );

        borrowRequest.duration = loanOffer.duration - (seed % 10_000);
        borrowRequest.signature = _signProposal(borrowRequest, borrowerPrivateKey);

        if (questionType == IPredictDotLoan.QuestionType.Binary) {
            _mintCTF(borrower, collateralAmount);
        } else {
            _mintNegRiskCTF(borrower, collateralAmount);
        }

        mockERC20.mint(lender, loanAmount);

        _trackCurrentContractPositionBalance(borrowRequest.questionType, borrowRequest.outcome);

        vm.prank(seed % 2 == 0 ? borrower : lender);
        predictDotLoan.matchProposals(borrowRequest, loanOffer);

        _trackCollateralDeposited(
            borrowRequest.questionType,
            borrowRequest.outcome,
            _trackContractPositionBalanceChange(borrowRequest.questionType, borrowRequest.outcome)
        );
    }

    function repay(uint256 seed) public countCall("repay") {
        uint256 lastLoanId = _getNextLoanId() - 1;
        if (lastLoanId < 1) return;
        uint256 loanId = bound(seed, 1, lastLoanId);
        (
            address borrower,
            ,
            ,
            ,
            ,
            ,
            uint256 startTime,
            ,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,

        ) = predictDotLoan.loans(loanId);
        if (status != IPredictDotLoan.LoanStatus.Active) return;
        if (callTime == 0 && vm.getBlockTimestamp() <= startTime) {
            vm.warp(startTime + (seed % 86_400) + 1);
        }
        uint256 debt = predictDotLoan.calculateDebt(loanId);
        if (debt == 0) return;
        mockERC20.mint(borrower, debt);
        (IPredictDotLoan.QuestionType questionType, bool outcome) = _getLoanQuestionTypeAndOutcome(loanId);
        _trackCurrentContractPositionBalance(questionType, outcome);
        vm.startPrank(borrower);
        mockERC20.approve(address(predictDotLoan), type(uint256).max);
        predictDotLoan.repay(loanId, debt);
        vm.stopPrank();
        _trackCollateralWithdrawn(questionType, outcome, _trackContractPositionBalanceChange(questionType, outcome));
    }

    // TODO: Do batch refinancing also
    function refinance(uint256 seed) public countCall("refinance") {
        uint256 loanId;
        {
            uint256 lastLoanId = _getNextLoanId() - 1;
            if (lastLoanId < 1) return;
            loanId = bound(seed, 1, lastLoanId);
        }
        (
            address _borrower,
            ,
            ,
            uint256 collateralAmount,
            ,
            uint256 interestRatePerSecond,
            ,
            ,
            ,
            IPredictDotLoan.LoanStatus status,

        ) = predictDotLoan.loans(loanId);
        if (status != IPredictDotLoan.LoanStatus.Active) return;
        (IPredictDotLoan.QuestionType questionType, bool outcome) = _getLoanQuestionTypeAndOutcome(loanId);
        uint256 privateKey = bound(seed, 1, 100);
        if (vm.addr(privateKey) == _borrower) {
            privateKey = uint256(keccak256(abi.encode(privateKey)));
        }
        if (vm.addr(privateKey) == _getLoanLender(loanId)) {
            privateKey = uint256(keccak256(abi.encode(privateKey)));
        }
        uint256 newInterestRatePerSecond = bound(seed, 1 ether + 2, 1 ether + TEN_THOUSAND_APY);
        if (newInterestRatePerSecond > interestRatePerSecond) {
            newInterestRatePerSecond = interestRatePerSecond - 1;
            if (newInterestRatePerSecond == 1 ether) {
                newInterestRatePerSecond = interestRatePerSecond;
            }
        }
        uint256 debt = predictDotLoan.calculateDebt(loanId);
        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(
            privateKey,
            collateralAmount * 2,
            ((collateralAmount * 2) *
                (debt + (debt * _getProtocolFeeBasisPoints()) / (10_000 - _getProtocolFeeBasisPoints()))) /
                collateralAmount,
            newInterestRatePerSecond,
            questionType,
            outcome
        );
        // Not sure how it's possible, but it's happening occasionally and I will just leave it here for now
        if (proposal.collateralAmount < proposal.loanAmount) return;
        address lender = vm.addr(privateKey);
        mockERC20.mint(lender, proposal.loanAmount);
        vm.prank(lender);
        mockERC20.approve(address(predictDotLoan), type(uint256).max);
        _trackCurrentContractPositionBalance(proposal.questionType, proposal.outcome);
        vm.prank(_borrower);
        predictDotLoan.refinance(IPredictDotLoan.Refinancing({loanId: loanId, proposal: proposal}));
        collateralTokenType[_getNextLoanId() - 1] = collateralTokenType[loanId];
    }

    function call(uint256 seed) public countCall("call") {
        uint256 lastLoanId = _getNextLoanId() - 1;
        if (lastLoanId < 1) return;

        uint256 loanId = bound(seed, 1, lastLoanId);

        (
            ,
            address lender,
            ,
            ,
            ,
            ,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,

        ) = predictDotLoan.loans(loanId);

        if (status != IPredictDotLoan.LoanStatus.Active || callTime != 0) {
            return;
        }

        if (vm.getBlockTimestamp() < startTime + minimumDuration) {
            vm.warp(startTime + minimumDuration);
        }

        (IPredictDotLoan.QuestionType questionType, bool outcome) = _getLoanQuestionTypeAndOutcome(loanId);

        _trackCurrentContractPositionBalance(questionType, outcome);

        vm.prank(lender);
        predictDotLoan.call(loanId);

        _trackCollateralWithdrawn(questionType, outcome, _trackContractPositionBalanceChange(questionType, outcome));
    }

    function auction(uint256 seed) public countCall("auction") {
        uint256 lastLoanId = _getNextLoanId() - 1;
        if (lastLoanId < 1) return;

        uint256 loanId = bound(seed, 1, lastLoanId);

        (
            ,
            address lender,
            ,
            uint256 collateralAmount,
            ,
            ,
            ,
            ,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status,

        ) = predictDotLoan.loans(loanId);

        if (status != IPredictDotLoan.LoanStatus.Called || vm.getBlockTimestamp() > callTime + 1 days) {
            return;
        }

        if (vm.getBlockTimestamp() <= callTime) {
            vm.warp(callTime + (seed % 86_400) + 1);
        }

        uint256 debt = predictDotLoan.calculateDebt(loanId);
        uint256 protocolFee = (debt * _getProtocolFeeBasisPoints()) / (10_000 - _getProtocolFeeBasisPoints());

        // Collateralization ratio must be at least 100%
        if (debt + protocolFee > collateralAmount) {
            return;
        }

        address whiteKnight = actors[bound(seed, 0, 99)];
        if (whiteKnight == lender) {
            whiteKnight = vm.addr(uint256(keccak256(abi.encodePacked(bound(seed, 0, 99)))));
        }

        mockERC20.mint(whiteKnight, debt + protocolFee);

        vm.startPrank(whiteKnight);
        mockERC20.approve(address(predictDotLoan), type(uint256).max);
        predictDotLoan.auction(loanId, predictDotLoan.auctionCurrentInterestRatePerSecond(loanId));
        vm.stopPrank();

        // A new loan is created when the loan is auctioned
        collateralTokenType[_getNextLoanId() - 1] = collateralTokenType[loanId];
    }

    function seize(uint256 seed) public countCall("seize") {
        uint256 lastLoanId = _getNextLoanId() - 1;
        if (lastLoanId < 1) return;

        uint256 loanId = bound(seed, 1, lastLoanId);

        (, address lender, , , , , , , uint256 callTime, IPredictDotLoan.LoanStatus status, ) = predictDotLoan.loans(
            loanId
        );

        if (status != IPredictDotLoan.LoanStatus.Called || vm.getBlockTimestamp() <= callTime + 1 days) {
            return;
        }

        (IPredictDotLoan.QuestionType questionType, bool outcome) = _getLoanQuestionTypeAndOutcome(loanId);

        _trackCurrentContractPositionBalance(questionType, outcome);

        vm.prank(lender);
        predictDotLoan.seize(loanId);

        _trackCollateralWithdrawn(questionType, outcome, _trackContractPositionBalanceChange(questionType, outcome));
    }

    function cancel(uint256 seed) public countCall("cancel") {
        uint256 salt = seed % _getNextLoanId();
        if (salts[salt].length > 0) {
            address[] storage users = salts[salt];
            address user = users[0];
            salts[salt][0] = users[salts[salt].length - 1];
            salts[salt].pop();

            IPredictDotLoan.SaltCancellationRequest[] memory requests = new IPredictDotLoan.SaltCancellationRequest[](
                1
            );
            requests[0] = IPredictDotLoan.SaltCancellationRequest({
                salt: salt,
                lending: seed % 2 == 0,
                borrowing: seed % 2 == 1
            });
            vm.prank(user);
            predictDotLoan.cancel(requests);
        }
    }

    function incrementNonces(uint256 seed) public countCall("incrementNonces") {
        vm.prank(vm.addr(bound(seed, 1, 100)));
        predictDotLoan.incrementNonces(seed % 2 == 0, seed % 2 == 1);
    }

    function updateProtocolFeeBasisPoints(uint256 seed) public countCall("updateProtocolFeeBasisPoints") {
        vm.prank(owner);
        predictDotLoan.updateProtocolFeeBasisPoints(uint8(seed % 201));
    }

    function toggleAutoRefinancingEnabled(uint256 seed) public countCall("toggleAutoRefinancingEnabled") {
        address user = vm.addr(bound(seed, 1, 100));
        vm.prank(user);
        predictDotLoan.toggleAutoRefinancingEnabled();
    }

    function updateMinimumOrderFeeRate(uint256 seed) public countCall("updateMinimumOrderFeeRate") {
        vm.prank(owner);
        predictDotLoan.updateMinimumOrderFeeRate(uint16(seed % 51));
    }

    function _generateBorrowRequest(
        uint256 privateKey,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 interestRatePerSecond,
        IPredictDotLoan.QuestionType questionType,
        bool outcome
    ) internal returns (IPredictDotLoan.Proposal memory proposal) {
        address borrower = vm.addr(privateKey);

        proposal = _generateBaseProposal(collateralAmount, loanAmount, interestRatePerSecond, questionType, outcome);
        proposal.from = borrower;
        salts[proposal.salt].push(borrower);
        proposal.proposalType = IPredictDotLoan.ProposalType.BorrowRequest;

        (, uint128 borrowingNonce) = predictDotLoan.nonces(borrower);
        proposal.nonce = borrowingNonce;

        proposal.signature = _signProposal(proposal, privateKey);
    }

    function _generateLoanOffer(
        uint256 privateKey,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 interestRatePerSecond,
        IPredictDotLoan.QuestionType questionType,
        bool outcome
    ) internal returns (IPredictDotLoan.Proposal memory proposal) {
        address lender = vm.addr(privateKey);

        proposal = _generateBaseProposal(collateralAmount, loanAmount, interestRatePerSecond, questionType, outcome);
        proposal.from = lender;
        salts[proposal.salt].push(lender);
        proposal.proposalType = IPredictDotLoan.ProposalType.LoanOffer;

        (uint128 lendingNonce, ) = predictDotLoan.nonces(lender);
        proposal.nonce = lendingNonce;

        proposal.signature = _signProposal(proposal, privateKey);
    }

    function _generateBaseProposal(
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 interestRatePerSecond,
        IPredictDotLoan.QuestionType questionType,
        bool outcome
    ) internal returns (IPredictDotLoan.Proposal memory proposal) {
        proposal.loanAmount = loanAmount;
        proposal.collateralAmount = collateralAmount;
        proposal.duration = 1 days;
        proposal.validUntil = vm.getBlockTimestamp() + 1 days;

        if (questionType == IPredictDotLoan.QuestionType.Binary) {
            proposal.questionId = questionId;
        } else if (questionType == IPredictDotLoan.QuestionType.NegRisk) {
            proposal.questionId = negRiskQuestionId;
        }
        proposal.questionType = questionType;
        proposal.outcome = outcome;
        proposal.interestRatePerSecond = interestRatePerSecond;
        proposal.protocolFeeBasisPoints = _getProtocolFeeBasisPoints();
        proposal.salt = ++globalSaltCounter;
    }

    function _signProposal(
        IPredictDotLoan.Proposal memory proposal,
        uint256 privateKey
    ) private view returns (bytes memory signature) {
        bytes32 digest = predictDotLoan.hashProposal(proposal);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _mintCTF(address to, uint256 amount) internal {
        mockERC20.mint(to, amount);

        bytes32 conditionId = CTHelpers.getConditionId(address(mockUmaCtfAdapter), questionId, 2);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        vm.startPrank(to);
        mockERC20.approve(address(mockCTF), amount);
        mockCTF.splitPosition(IERC20(address(mockERC20)), bytes32(0), conditionId, partition, amount);
        mockCTF.setApprovalForAll(address(predictDotLoan), true);
        vm.stopPrank();
    }

    function _mintNegRiskCTF(address to, uint256 amount) internal {
        mockERC20.mint(to, amount);

        bytes32 conditionId = mockNegRiskAdapter.getConditionId(negRiskQuestionId);

        mockNegRiskAdapter.prepareCondition(negRiskQuestionId);

        uint256[] memory partition = new uint256[](2);
        partition[0] = 1;
        partition[1] = 2;

        mockNegRiskAdapter.prepareCondition(negRiskQuestionId);

        vm.startPrank(to);
        mockERC20.approve(address(mockNegRiskAdapter), amount);
        mockNegRiskAdapter.splitPosition(address(mockERC20), bytes32(0), conditionId, partition, amount);
        mockCTF.setApprovalForAll(address(predictDotLoan), true);
        vm.stopPrank();
    }

    function _chooseInterestRatePerSecond(uint256 seed) private pure returns (uint256 interestRatePerSecond) {
        interestRatePerSecond = 1 ether + (seed % TEN_THOUSAND_APY) + 1;
    }

    function _chooseQuestionType(uint256 seed) private pure returns (IPredictDotLoan.QuestionType questionType) {
        questionType = seed % 2 == 0 ? IPredictDotLoan.QuestionType.Binary : IPredictDotLoan.QuestionType.NegRisk;
    }

    function _chooseOutcome(uint256 seed) private pure returns (bool outcome) {
        outcome = seed % 2 == 0;
    }

    function _chooseFulfillAmount(
        uint256 seed,
        IPredictDotLoan.Proposal memory proposal
    ) private view returns (uint256 fulfillAmount) {
        (, , uint256 loanAmount) = predictDotLoan.getFulfillment(proposal);
        uint256 maxFulfillAmount = proposal.loanAmount - loanAmount;
        fulfillAmount = maxFulfillAmount > proposal.loanAmount / 10
            ? bound(seed, proposal.loanAmount / 10, maxFulfillAmount)
            : maxFulfillAmount;
    }

    function _getLoanLender(uint256 loanId) private view returns (address lender) {
        (, lender, , , , , , , , , ) = predictDotLoan.loans(loanId);
    }

    function _getLoanQuestionTypeAndOutcome(
        uint256 loanId
    ) private view returns (IPredictDotLoan.QuestionType questionType, bool outcome) {
        questionType = uint8(collateralTokenType[loanId]) < 2
            ? IPredictDotLoan.QuestionType.Binary
            : IPredictDotLoan.QuestionType.NegRisk;

        outcome = uint8(collateralTokenType[loanId]) % 2 == 0;
    }

    function _trackCurrentContractPositionBalance(IPredictDotLoan.QuestionType questionType, bool outcome) private {
        uint256 positionId = _derivePositionId(questionType, outcome);
        accountPositionBalances[address(predictDotLoan)][positionId] = mockCTF.balanceOf(
            address(predictDotLoan),
            positionId
        );
    }

    function _trackContractPositionBalanceChange(
        IPredictDotLoan.QuestionType questionType,
        bool outcome
    ) private returns (uint256 delta) {
        uint256 positionId = _derivePositionId(questionType, outcome);
        uint256 currentBalance = mockCTF.balanceOf(address(predictDotLoan), positionId);
        uint256 lastRecordedBalance = accountPositionBalances[address(predictDotLoan)][positionId];
        delta = currentBalance > lastRecordedBalance
            ? currentBalance - lastRecordedBalance
            : lastRecordedBalance - currentBalance;
        accountPositionBalances[address(predictDotLoan)][positionId] = 0;
    }

    function _trackCollateralDeposited(
        IPredictDotLoan.QuestionType questionType,
        bool outcome,
        uint256 collateralAmount
    ) private {
        uint256 loanId = _getNextLoanId() - 1;
        if (questionType == IPredictDotLoan.QuestionType.Binary) {
            if (outcome) {
                collateralTokenType[loanId] = CollateralTokenType.BinaryYes;
                ghost_CTF_binaryYes_depositedSum += collateralAmount;
            } else {
                collateralTokenType[loanId] = CollateralTokenType.BinaryNo;
                ghost_CTF_binaryNo_depositedSum += collateralAmount;
            }
        } else {
            if (outcome) {
                collateralTokenType[loanId] = CollateralTokenType.NegRiskYes;
                ghost_CTF_negRiskYes_depositedSum += collateralAmount;
            } else {
                collateralTokenType[loanId] = CollateralTokenType.NegRiskNo;
                ghost_CTF_negRiskNo_depositedSum += collateralAmount;
            }
        }
    }

    function _trackCollateralWithdrawn(
        IPredictDotLoan.QuestionType questionType,
        bool outcome,
        uint256 collateralAmount
    ) private {
        if (questionType == IPredictDotLoan.QuestionType.Binary) {
            if (outcome) {
                ghost_CTF_binaryYes_withdrawnSum += collateralAmount;
            } else {
                ghost_CTF_binaryNo_withdrawnSum += collateralAmount;
            }
        } else {
            if (outcome) {
                ghost_CTF_negRiskYes_withdrawnSum += collateralAmount;
            } else {
                ghost_CTF_negRiskNo_withdrawnSum += collateralAmount;
            }
        }
    }

    function _derivePositionId(
        IPredictDotLoan.QuestionType questionType,
        bool outcome
    ) private view returns (uint256 positionId) {
        if (questionType == IPredictDotLoan.QuestionType.Binary) {
            bytes32 conditionId = _getConditionId(address(mockUmaCtfAdapter), questionId, 2);
            bytes32 collectionId = mockCTF.getCollectionId(bytes32(0), conditionId, outcome ? 1 : 2);
            positionId = _getPositionId(IERC20(address(mockERC20)), collectionId);
        } else {
            positionId = mockNegRiskAdapter.getPositionId(negRiskQuestionId, outcome);
        }
    }

    function _getConditionId(
        address oracle,
        bytes32 _questionId,
        uint outcomeSlotCount
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(oracle, _questionId, outcomeSlotCount));
    }

    function _getPositionId(IERC20 collateralToken, bytes32 collectionId) private pure returns (uint) {
        return uint(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }

    function _getNextLoanId() private view returns (uint256) {
        return uint256(vm.load(address(predictDotLoan), bytes32(uint256(8))));
    }

    function _getProtocolFeeBasisPoints() internal view returns (uint8) {
        bytes32 slot12 = vm.load(address(predictDotLoan), bytes32(uint256(12)));
        return uint8(uint256(slot12) >> 160);
    }

    function _getMinimumOrderFeeRate() internal view returns (uint16) {
        bytes32 slot12 = vm.load(address(predictDotLoan), bytes32(uint256(12)));
        return uint16(uint256(slot12) >> 168);
    }
}

contract PredictDotLoan_Invariants is TestHelpers {
    Handler public handler;

    MockBlastSwissKnife public mockBlastSwissKnife;

    function setUp() public {
        mockCTF = new ConditionalTokens("https://predict.fun");

        mockERC20 = new MockERC20("USDB", "USDB");
        mockBlastSwissKnife = new MockBlastSwissKnife();

        mockUmaCtfAdapter = new MockUmaCtfAdapter(address(mockCTF));
        // TODO: Why does this throw an EVM revert? Just going to use
        // the same adapter for both binary and neg risk for now, even
        // though the UMA CTF adapter is different for each.
        // mockNegRiskUmaCtfAdapter = new MockUmaCtfAdapter(address(mockCTF));
        mockNegRiskUmaCtfAdapter = mockUmaCtfAdapter;
        mockNegRiskAdapter = new MockNegRiskAdapter(address(mockCTF), address(mockERC20));

        mockNegRiskOperator = new MockNegRiskOperator(address(mockNegRiskAdapter));
        mockNegRiskOperator.setQuestionId(negRiskQuestionId, MockNegRiskIdLib.getQuestionId(_getNegRiskMarketId(), 0));

        mockUmaCtfAdapter.prepareCondition(SINGLE_OUTCOME_QUESTION);
        mockUmaCtfAdapter.setPayoutStatus(questionId, MockUmaCtfAdapter.PayoutStatus.PriceNotAvailable);

        mockNegRiskAdapter.prepareCondition(negRiskQuestionId);
        mockNegRiskUmaCtfAdapter.prepareCondition(MULTI_OUTCOMES_QUESTION);
        mockNegRiskUmaCtfAdapter.setPayoutStatus(negRiskQuestionId, MockUmaCtfAdapter.PayoutStatus.PriceNotAvailable);

        mockCTFExchange = new MockCTFExchange(address(mockCTF), address(mockERC20));
        mockNegRiskCTFExchange = new MockCTFExchange(address(mockNegRiskAdapter), address(mockERC20));

        addressFinder = new AddressFinder();
        addressFinder.changeImplementationAddress("Blast", address(mockBlastSwissKnife));
        addressFinder.changeImplementationAddress("BlastPoints", address(mockBlastSwissKnife));
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

        vm.prank(owner);
        predictDotLoan.updateMinimumOrderFeeRate(0);

        mockCTFExchange.addOperator(address(predictDotLoan));
        mockNegRiskCTFExchange.addOperator(address(predictDotLoan));
        mockNegRiskAdapter.addAdmin(address(mockNegRiskCTFExchange));

        bytes32 conditionId = mockCTF.getConditionId(address(mockUmaCtfAdapter), questionId, 2);
        mockCTFExchange.registerToken(_getPositionId(true), _getPositionId(false), conditionId);

        bytes32 negRiskConditionId = mockNegRiskAdapter.getConditionId(negRiskQuestionId);
        mockNegRiskCTFExchange.registerToken(
            mockNegRiskAdapter.getPositionId(negRiskQuestionId, true),
            mockNegRiskAdapter.getPositionId(negRiskQuestionId, false),
            negRiskConditionId
        );

        handler = new Handler(
            owner,
            predictDotLoan,
            mockCTF,
            mockERC20,
            mockUmaCtfAdapter,
            mockNegRiskUmaCtfAdapter,
            mockNegRiskAdapter
        );

        targetContract(address(handler));
    }

    /**
     * Invariant A: predict.loan should never hold any ERC-20 tokens.
     */
    function invariant_A() public view {
        assertEq(mockERC20.balanceOf(address(predictDotLoan)), 0);
    }

    /**
     * Invariant B: Withdrawn amount should never exceed deposited amount.
     */
    function invariant_B() public view {
        assertGe(handler.ghost_CTF_binaryYes_depositedSum(), handler.ghost_CTF_binaryYes_withdrawnSum());
        assertGe(handler.ghost_CTF_binaryNo_depositedSum(), handler.ghost_CTF_binaryNo_withdrawnSum());
        assertGe(handler.ghost_CTF_negRiskYes_depositedSum(), handler.ghost_CTF_negRiskYes_withdrawnSum());
        assertGe(handler.ghost_CTF_negRiskNo_depositedSum(), handler.ghost_CTF_negRiskNo_withdrawnSum());
    }

    /**
     * Invariant C: The CTF contract should hold exactly the net amount of collateral that has been deposited.
     */
    function invariant_C() public view {
        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)),
            handler.ghost_CTF_binaryYes_depositedSum() - handler.ghost_CTF_binaryYes_withdrawnSum()
        );
        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), _getPositionId(false)),
            handler.ghost_CTF_binaryNo_depositedSum() - handler.ghost_CTF_binaryNo_withdrawnSum()
        );

        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), mockNegRiskAdapter.getPositionId(negRiskQuestionId, true)),
            handler.ghost_CTF_negRiskYes_depositedSum() - handler.ghost_CTF_negRiskYes_withdrawnSum()
        );
        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), mockNegRiskAdapter.getPositionId(negRiskQuestionId, false)),
            handler.ghost_CTF_negRiskNo_depositedSum() - handler.ghost_CTF_negRiskNo_withdrawnSum()
        );
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
