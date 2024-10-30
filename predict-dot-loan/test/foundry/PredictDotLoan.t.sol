// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {BlastPredictDotLoan} from "../../contracts/BlastPredictDotLoan.sol";
import {YieldMode, GasMode} from "../../contracts/interfaces/IBlast.sol";
import {IPredictDotLoan} from "../../contracts/interfaces/IPredictDotLoan.sol";

import {TestHelpers} from "./TestHelpers.sol";

import {MockERC20} from "../mock/MockERC20.sol";
import {MockUmaCtfAdapter} from "../mock/MockUmaCtfAdapter.sol";
import {ConditionalTokens} from "../mock/ConditionalTokens/ConditionalTokens.sol";
import {MockCTFExchange} from "../mock/CTFExchange/MockCTFExchange.sol";
import {MockNegRiskAdapter} from "../mock/NegRiskAdapter/MockNegRiskAdapter.sol";
import {MockNegRiskOperator} from "../mock/NegRiskAdapter/MockNegRiskOperator.sol";

contract PredictDotLoan_Test is TestHelpers {
    function setUp() public {
        _deploy();

        _mintTokensAndApproveForSetup(LOAN_AMOUNT, COLLATERAL_AMOUNT);
    }

    function test_setUpState() public view {
        (YieldMode yieldMode, GasMode gasMode, address governor) = mockBlastYield.config(address(predictDotLoan));
        assertEq(uint8(yieldMode), uint8(YieldMode.CLAIMABLE));
        assertEq(uint8(gasMode), uint8(GasMode.CLAIMABLE));
        assertEq(governor, owner);

        assertEq(mockBlastPoints.contractOperators(address(predictDotLoan)), blastPointsOperator);

        assertEq(address(predictDotLoan.CTF_EXCHANGE()), address(mockCTFExchange));
        assertEq(address(predictDotLoan.NEG_RISK_CTF_EXCHANGE()), address(mockNegRiskCTFExchange));

        assertTrue(predictDotLoan.hasRole(predictDotLoan.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(predictDotLoan.hasRole(keccak256("REFINANCIER_ROLE"), bot));

        assertEq(_getProtocolFeeBasisPoints(), 0);
        assertEq(_getMinimumOrderFeeRate(), 0);

        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = predictDotLoan.eip712Domain();

        assertEq(fields, hex"0f");
        assertEq(name, "predict.loan");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(predictDotLoan));
        assertEq(salt, bytes32(0));
        assertEq(extensions.length, 0);
    }

    function test_setUpState_RevertIf_OnlyOneCTFAllowed() public {
        mockUmaCtfAdapter = new MockUmaCtfAdapter(address(mockCTF));
        mockNegRiskAdapter = new MockNegRiskAdapter(
            address(new ConditionalTokens("https://predict.fail")),
            address(mockERC20)
        );

        mockCTFExchange = new MockCTFExchange(address(mockCTF), address(mockERC20));
        mockNegRiskCTFExchange = new MockCTFExchange(address(mockNegRiskAdapter), address(mockERC20));

        vm.expectRevert(IPredictDotLoan.OnlyOneCTFAllowed.selector);
        new BlastPredictDotLoan(
            protocolFeeRecipient,
            address(mockCTFExchange),
            address(mockNegRiskCTFExchange),
            address(mockUmaCtfAdapter),
            address(mockNegRiskUmaCtfAdapter),
            address(mockNegRiskOperator),
            address(addressFinder),
            owner
        );
    }

    function test_setUpState_RevertIf_InvalidNegRiskOperator() public {
        mockNegRiskOperator = new MockNegRiskOperator(address(0));

        vm.expectRevert(IPredictDotLoan.InvalidNegRiskOperator.selector);
        new BlastPredictDotLoan(
            protocolFeeRecipient,
            address(mockCTFExchange),
            address(mockNegRiskCTFExchange),
            address(mockUmaCtfAdapter),
            address(mockNegRiskUmaCtfAdapter),
            address(mockNegRiskOperator),
            address(addressFinder),
            owner
        );
    }

    function test_setUpState_RevertIf_OnlyOneLoanTokenAllowed() public {
        MockERC20 differentERC20 = new MockERC20("Different ERC20", "DIFF");
        mockNegRiskCTFExchange = new MockCTFExchange(address(mockNegRiskAdapter), address(differentERC20));

        vm.expectRevert(IPredictDotLoan.OnlyOneLoanTokenAllowed.selector);
        new BlastPredictDotLoan(
            protocolFeeRecipient,
            address(mockCTFExchange),
            address(mockNegRiskCTFExchange),
            address(mockUmaCtfAdapter),
            address(mockNegRiskUmaCtfAdapter),
            address(mockNegRiskOperator),
            address(addressFinder),
            owner
        );
    }

    function test_hashProposal() public view {
        IPredictDotLoan.Proposal memory loanOffer = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);
        assertEq(
            predictDotLoan.hashProposal(loanOffer),
            bytes32(0x6d393a11cfb314f2d231c90b9418fba5a5402bc159de79138e5923296d891429)
        );

        IPredictDotLoan.Proposal memory borrowRequest = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);
        assertEq(
            predictDotLoan.hashProposal(borrowRequest),
            bytes32(0xdee5a2f50c573c6c3f2a115fb91412b1f452a1c67c5ad14cd0dfadd0fda72972)
        );
    }

    // TODO: Fuzz amounts and interest rate

    function testFuzz_acceptLoanOffer(uint8 protocolFeeBasisPoints) public {
        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        _assertProposalAcceptedEmitted(predictDotLoan.hashProposal(proposal), borrower, lender);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);

        assertEq(
            mockERC20.balanceOf(borrower),
            proposal.loanAmount - (proposal.loanAmount * protocolFeeBasisPoints) / 10_000
        );
        assertEq(mockERC20.balanceOf(protocolFeeRecipient), (proposal.loanAmount * protocolFeeBasisPoints) / 10_000);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        _assertLoanOfferFulfillmentData(proposal);

        _assertLoanCreated();
    }

    function testFuzz_acceptLoanOffer_NegRisk(uint8 protocolFeeBasisPoints) public {
        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        IPredictDotLoan.Proposal memory proposal = _generateLoanOffer(IPredictDotLoan.QuestionType.NegRisk);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        _assertProposalAcceptedEmitted_NegRisk(predictDotLoan.hashProposal(proposal), borrower, lender);

        vm.prank(borrower);
        predictDotLoan.acceptLoanOffer(proposal, proposal.loanAmount);

        assertEq(
            mockERC20.balanceOf(borrower),
            proposal.loanAmount - (proposal.loanAmount * protocolFeeBasisPoints) / 10_000
        );
        assertEq(mockERC20.balanceOf(protocolFeeRecipient), (proposal.loanAmount * protocolFeeBasisPoints) / 10_000);
        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), mockNegRiskAdapter.getPositionId(negRiskQuestionId, true)),
            proposal.collateralAmount
        );
        _assertLoanOfferFulfillmentData(proposal);

        _assertLoanCreated_NegRisk();
    }

    function testFuzz_acceptBorrowRequest(uint8 protocolFeeBasisPoints) public {
        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.Binary);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        _assertProposalAcceptedEmitted(predictDotLoan.hashProposal(proposal), borrower, lender);

        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);

        assertEq(
            mockERC20.balanceOf(borrower),
            proposal.loanAmount - (proposal.loanAmount * protocolFeeBasisPoints) / 10_000
        );
        assertEq(mockERC20.balanceOf(protocolFeeRecipient), (proposal.loanAmount * protocolFeeBasisPoints) / 10_000);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), proposal.collateralAmount);
        _assertBorrowRequestFulfillmentData(proposal);

        _assertLoanCreated();
    }

    function testFuzz_acceptBorrowRequest_NegRiskCTF(uint8 protocolFeeBasisPoints) public {
        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        IPredictDotLoan.Proposal memory proposal = _generateBorrowRequest(IPredictDotLoan.QuestionType.NegRisk);

        _assertBalanceAndFulfillmentBeforeExecution(borrower, lender, proposal);

        _assertProposalAcceptedEmitted_NegRisk(predictDotLoan.hashProposal(proposal), borrower, lender);

        vm.prank(lender);
        predictDotLoan.acceptBorrowRequest(proposal, proposal.loanAmount);

        assertEq(
            mockERC20.balanceOf(borrower),
            proposal.loanAmount - (proposal.loanAmount * protocolFeeBasisPoints) / 10_000
        );
        assertEq(mockERC20.balanceOf(protocolFeeRecipient), (proposal.loanAmount * protocolFeeBasisPoints) / 10_000);
        assertEq(
            mockCTF.balanceOf(address(predictDotLoan), mockNegRiskAdapter.getPositionId(negRiskQuestionId, true)),
            proposal.collateralAmount
        );
        _assertBorrowRequestFulfillmentData(proposal);

        _assertLoanCreated_NegRisk();
    }

    function test_repay_LoanHasNotBeenCalled() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + 12 hours);

        uint256 debt = predictDotLoan.calculateDebt(1);
        assertEq(debt, EXPECTED_DEBT_AFTER_12_HOURS);

        mockERC20.mint(borrower, debt - LOAN_AMOUNT);

        vm.startPrank(borrower);
        mockERC20.approve(address(predictDotLoan), debt);
        predictDotLoan.repay(1, debt);
        vm.stopPrank();

        IPredictDotLoan.LoanStatus status = _getLoanStatus(1);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Repaid));

        assertEq(mockERC20.balanceOf(borrower), 0);
        assertEq(mockERC20.balanceOf(lender), debt);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), COLLATERAL_AMOUNT);

        debt = predictDotLoan.calculateDebt(1);
        assertEq(debt, 0);
    }

    function test_repay_LoanHasBeenCalled() public {
        testFuzz_acceptLoanOffer(0);

        // The owed amount does not change after the loan has been called
        vm.warp(vm.getBlockTimestamp() + LOAN_DURATION + 12 hours);

        vm.prank(lender);
        predictDotLoan.call(1);

        vm.warp(vm.getBlockTimestamp() + 2 days);

        uint256 debt = predictDotLoan.calculateDebt(1);
        assertEq(debt, 700.274051803818440200 ether);

        mockERC20.mint(borrower, debt - LOAN_AMOUNT);

        vm.startPrank(borrower);
        mockERC20.approve(address(predictDotLoan), debt);
        predictDotLoan.repay(1, debt);
        vm.stopPrank();

        IPredictDotLoan.LoanStatus status = _getLoanStatus(1);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Repaid));

        assertEq(mockERC20.balanceOf(borrower), 0);
        assertEq(mockERC20.balanceOf(lender), debt);
        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(borrower, _getPositionId(true)), COLLATERAL_AMOUNT);

        debt = predictDotLoan.calculateDebt(1);
        assertEq(debt, 0);
    }

    function test_call() public {
        testFuzz_acceptLoanOffer(0);

        vm.warp(vm.getBlockTimestamp() + LOAN_DURATION);

        expectEmitCheckAll();
        emit LoanCalled(1);

        vm.prank(lender);
        predictDotLoan.call(1);

        (, , , , , , , , uint256 callTime, IPredictDotLoan.LoanStatus status, ) = predictDotLoan.loans(1);

        assertEq(callTime, vm.getBlockTimestamp());
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Called));
    }

    function testFuzz_auction(uint256 timeElapsed, uint8 protocolFeeBasisPoints) public {
        vm.assume(timeElapsed > 0 && timeElapsed <= AUCTION_DURATION);
        test_call();

        vm.warp(vm.getBlockTimestamp() + timeElapsed);

        uint256 currentInterestRatePerSecond = predictDotLoan.auctionCurrentInterestRatePerSecond(1);
        assertGt(currentInterestRatePerSecond, ONE);

        uint256 debt = predictDotLoan.calculateDebt(1);
        assertGt(debt, LOAN_AMOUNT);

        _updateProtocolFeeRecipientAndBasisPoints(protocolFeeBasisPoints);

        uint256 expectedProtocolFee = (debt * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints);

        mockERC20.mint(whiteKnight, debt + expectedProtocolFee);

        vm.startPrank(whiteKnight);

        mockERC20.approve(address(predictDotLoan), debt + expectedProtocolFee);

        expectEmitCheckAll();
        emit LoanTransferred(1, debt, expectedProtocolFee, 2, whiteKnight, currentInterestRatePerSecond);

        predictDotLoan.auction(1, currentInterestRatePerSecond);

        vm.stopPrank();

        assertEq(mockERC20.balanceOf(whiteKnight), 0);
        assertEq(mockERC20.balanceOf(lender), debt);
        assertEq(mockERC20.balanceOf(protocolFeeRecipient), expectedProtocolFee);
        assertEq(uint8(_getLoanStatus(1)), uint8(IPredictDotLoan.LoanStatus.Auctioned));

        {
            (, , , , uint256 loanAmount, uint256 interestRatePerSecond, , , , , ) = predictDotLoan.loans(2);

            assertEq(loanAmount, debt + expectedProtocolFee);
            assertEq(interestRatePerSecond, currentInterestRatePerSecond);
        }

        (
            address _borrower,
            address _lender,
            uint256 positionId,
            uint256 collateralAmount,
            ,
            ,
            uint256 startTime,
            uint256 minimumDuration,
            uint256 callTime,
            IPredictDotLoan.LoanStatus status2,
            IPredictDotLoan.QuestionType questionType
        ) = predictDotLoan.loans(2);

        assertEq(_borrower, borrower);
        assertEq(_lender, whiteKnight);
        assertEq(positionId, _getPositionId(true));
        assertEq(collateralAmount, COLLATERAL_AMOUNT);
        assertEq(startTime, vm.getBlockTimestamp());
        assertEq(minimumDuration, 0);
        assertEq(callTime, 0);
        assertEq(uint8(status2), uint8(IPredictDotLoan.LoanStatus.Active));
        assertEq(uint8(questionType), uint8(IPredictDotLoan.QuestionType.Binary));
        assertEq(_getNextLoanId(), 3);
    }

    function test_seize() public {
        test_call();

        vm.warp(vm.getBlockTimestamp() + AUCTION_DURATION + 1 seconds);

        expectEmitCheckAll();
        emit LoanDefaulted(1);

        vm.prank(lender);
        predictDotLoan.seize(1);

        IPredictDotLoan.LoanStatus status = _getLoanStatus(1);
        assertEq(uint8(status), uint8(IPredictDotLoan.LoanStatus.Defaulted));

        assertEq(mockCTF.balanceOf(address(predictDotLoan), _getPositionId(true)), 0);
        assertEq(mockCTF.balanceOf(lender, _getPositionId(true)), COLLATERAL_AMOUNT);
    }
}
