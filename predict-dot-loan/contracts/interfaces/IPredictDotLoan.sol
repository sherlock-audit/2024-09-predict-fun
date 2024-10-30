// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Order} from "./ICTFExchange.sol";

interface IPredictDotLoan {
    enum LoanStatus {
        None,
        Active,
        Repaid,
        Refinanced,
        Called,
        Auctioned,
        Defaulted
    }

    enum ProposalType {
        LoanOffer,
        BorrowRequest
    }

    enum QuestionType {
        Binary,
        NegRisk
    }

    /**
     * @notice A proposal can be a borrow request or a loan offer
     *
     * @param from The address of the proposal's originator
     * @param loanAmount The amount to borrow
     * @param collateralAmount The amount of collateral provided/required
     * @param questionType The collateral token's question type. The question type determines the collateral token's address
     * @param questionId The collateral token's question ID
     * @param outcome The collateral token's outcome, which is used together with the question ID and collateral token to derive the position's ID
     * @param interestRatePerSecond The desired/offered interest rate per second
     * @param duration The desired/offered loan duration
     * @param validUntil The timestamp until which the proposal is valid
     * @param salt A random number to prevent replay attacks
     * @param nonce The nonce of the proposal's originator
     * @param proposalType The type of the proposal (BorrowRequest or LoanOffer)
     * @param signature The proposal's signature
     * @param protocolFeeBasisPoints The proposal's accepted protocol fee basis points, it must be the same as the contract's current protocol fee basis points
     */
    struct Proposal {
        address from;
        uint256 loanAmount;
        uint256 collateralAmount;
        QuestionType questionType;
        bytes32 questionId;
        bool outcome;
        uint256 interestRatePerSecond;
        uint256 duration;
        uint256 validUntil;
        uint256 salt;
        uint256 nonce;
        ProposalType proposalType;
        bytes signature;
        uint256 protocolFeeBasisPoints;
    }

    struct Loan {
        address borrower;
        address lender;
        uint256 positionId;
        uint256 collateralAmount;
        uint256 loanAmount;
        uint256 interestRatePerSecond;
        uint256 startTime;
        uint256 minimumDuration;
        uint256 callTime;
        LoanStatus status;
        QuestionType questionType;
    }

    struct Fulfillment {
        bytes32 proposalId;
        uint256 collateralAmount;
        uint256 loanAmount;
    }

    struct Refinancing {
        uint256 loanId;
        Proposal proposal;
    }

    /**
     * @dev startTime is always going to be block.timestamp so we are not going to add
     *      it to the event. Indexers should just use block's timestamp.
     */
    struct RefinancingResult {
        bytes32 proposalId;
        uint256 refinancedLoanId;
        uint256 newLoanId;
        address lender;
        uint256 collateralAmount;
        uint256 loanAmount;
        uint256 interestRatePerSecond;
        uint256 minimumDuration;
        uint256 protocolFee;
    }

    struct Nonces {
        uint128 lending;
        uint128 borrowing;
    }

    struct SaltCancellationRequest {
        uint256 salt;
        bool lending;
        bool borrowing;
    }

    struct SaltCancellationStatus {
        bool lending;
        bool borrowing;
    }

    /*//////////////////////////////////////////////////////////////
                        LOAN LIFECYCLE EVENTS
    //////////////////////////////////////////////////////////////*/

    event LoanCalled(uint256 loanId);
    event LoanDefaulted(uint256 loanId);
    /**
     * @dev startTime is always going to be block.timestamp so we are not going to add
     *      it to the event. Indexers should just use block's timestamp.
     *
     *      loanAmount includes the protocol fee
     */
    event LoanRefinanced(
        bytes32 proposalId,
        uint256 refinancedLoanId,
        uint256 newLoanId,
        address indexed lender,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 interestRatePerSecond,
        uint256 minimumDuration,
        uint256 protocolFee
    );
    event LoansRefinanced(RefinancingResult[] results);

    event LoanRepaid(uint256 loanId, uint256 repaidAmount);
    event LoanTransferred(
        uint256 loanId,
        uint256 repaidAmount,
        uint256 protocolFee,
        uint256 newLoanId,
        address newLender,
        uint256 newInterestRatePerSecond
    );

    /**
     * @dev startTime is always going to be block.timestamp so we are not going to add
     *      it to the event. Indexers should just use block's timestamp.
     *
     *      collateralToken is always going to be CTF so we are not going to add it to the event neither.
     *
     *      loanAmount includes the protocol fee
     */
    event ProposalAccepted(
        uint256 loanId,
        bytes32 proposalId,
        address indexed borrower,
        address indexed lender,
        uint256 indexed positionId,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 protocolFee
    );

    /**
     * @dev startTime is always going to be block.timestamp so we are not going to add
     *      it to the event. Indexers should just use block's timestamp.
     *
     *      collateralToken is always going to be CTF so we are not going to add it to the event neither.
     *
     *      proposalType is always going to be LoanOffer so we are not going to add it to the event neither.
     *
     *      loanAmount includes the protocol fee
     */
    event OrderFilledUsingProposal(
        bytes32 proposalId,
        uint256 loanId,
        address indexed borrower,
        address indexed lender,
        uint256 indexed positionId,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 protocolFee
    );

    /**
     * @dev startTime is always going to be block.timestamp so we are not going to add
     *      it to the event. Indexers should just use block's timestamp.
     *
     *      collateralToken is always going to be CTF so we are not going to add it to the event neither.
     *
     *      loanAmount includes the protocol fee
     */
    event ProposalsMatched(
        bytes32 loanOfferProposalId,
        bytes32 borrowRequestProposalId,
        uint256 loanId,
        address indexed borrower,
        address indexed lender,
        uint256 indexed positionId,
        uint256 collateralAmount,
        uint256 loanAmount,
        uint256 protocolFee
    );

    /*//////////////////////////////////////////////////////////////
                            MISC EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev 0 = disabled, 1 = enabled
     */
    event AutoRefinancingEnabledToggled(address indexed user, uint256 preference);

    event MinimumOrderFeeRateUpdated(uint256 _minimumOrderFeeRate);
    event NoncesIncremented(uint256 lendingNonce, uint256 borrowingNonce);

    event ProtocolFeeBasisPointsUpdated(uint256 _protocolFeeBasisPoints);
    event ProtocolFeeRecipientUpdated(address _protocolFeeRecipient);
    event SaltsCancelled(address indexed user, SaltCancellationRequest[] requests);

    error AbnormalQuestionState();
    error AuctionIsOver();
    error AuctionNotOver();
    error AuctionNotStarted();
    error BorrowerDidNotEnableAutoRefinancing(address borrower);
    error CollateralizationRatioTooLow();
    error ContractOnlyAcceptsCTF();
    error MaxRepaymentAmountExceeded();
    error Expired();
    error FulfillAmountTooHigh();
    error FulfillAmountTooLow();
    error InsufficientCollateral();
    error InterestRatePerSecondTooHigh();
    error InterestRatePerSecondTooLow();
    error InvalidLoanStatus();
    error InvalidNegRiskOperator();
    error InvalidNonce();
    error InvalidSignature();
    error LenderIsBorrower();
    error LoanCannotBeRepaidInstantly();
    error LoanNotMatured();
    error MarketResolved();
    error NewLenderIsTheSameAsOldLender();
    error NoQuestionIdForOracleRequestId();
    error NoSaltCancellationRequests();
    error NotBorrowRequest();
    error NotCancelling();
    error NotIncrementing();
    error NotLoanOffer();
    error NotSellOrder();
    error OnlyOneCTFAllowed();
    error OnlyOneLoanTokenAllowed();
    error OrderDidNotFill();
    error OrderFeeRateTooLow();
    error PositionIdMismatch();
    error PositionIdNotTradeableOnExchange();
    error ProposalCancelled();
    error ProtocolFeeBasisPointsMismatch();
    error ProtocolFeeBasisPointsTooHigh();
    error QuestionResolved();
    error SaltAlreadyCancelled(uint256 salt);
    error SaltAlreadyUsed();
    error SellerMustBeThirdParty();
    error UnacceptableCollateralizationRatio();
    error UnacceptableDuration();
    error UnacceptableInterestRatePerSecond();
    error UnauthorizedCaller();
    error UnexpectedDurationShortening();
    error WorseInterestRatePerSecond();
    error ZeroAddress();

    /**
     * @notice Lenders can accept borrow requests by calling this function with borrow requests signed off-chain.
     *         Each fulfillment must fulfill at least 10% of the borrow amount. However, if there are less than 10% of the loan amount left to be fulfilled,
     *         the remaining amount will be fulfilled as long as it fills the rest of the order.
     *
     *         A protocol fee is charged on the fulfill amount. If the fulfill amount is 100 USDB and the protocol fee % is 1%, the borrower receives 99 USDB.
     *
     * @param proposal The borrow request to accept
     * @param fulfillAmount Loan amount to fulfill
     */
    function acceptBorrowRequest(Proposal calldata proposal, uint256 fulfillAmount) external;

    /**
     * @notice Borrowers can accept loan offers by calling this function with loan offers signed off-chain.
     *         Each fulfillment must fulfill at least 10% of the loan amount. However, if there are less than 10% of the loan amount left to be fulfilled,
     *         the remaining amount will be fulfilled as long as it fills the rest of the order.
     *
     *         A protocol fee is charged on the fulfill amount. If the fulfill amount is 100 USDB and the protocol fee % is 1%, the borrower receives 99 USDB.
     *
     * @param proposal The loan offer to accept
     * @param fulfillAmount Loan amount to fulfill
     */
    function acceptLoanOffer(Proposal calldata proposal, uint256 fulfillAmount) external;

    /**
     * @notice Borrowers can accept loan offers and then use the borrowed amount to fill an order on the CTF exchange.
     *
     *         A protocol fee is charged on top of the sell order's taker amount. If the taker amount is 100 USDB and the protocol fee % is 1%,
     *         the borrower receives 100 USDB, which is used to fill the order, and is charged 1.0101010101 USDB in protocol fee.
     *
     * @param exchangeOrder The exchange order to fill
     * @param proposal The loan offer to accept
     */
    function acceptLoanOfferAndFillOrder(Order calldata exchangeOrder, Proposal calldata proposal) external;

    /**
     * @notice Match a borrow request with a loan offer
     *         The loan offer must have a lower interest rate per second than the borrow request
     *         The borrow request must have a shorter duration than the loan offer
     *         The borrow request must have a collateralization ratio as good as the loan offer
     *         The fulfill amount is the lesser of the two loan amounts with already fulfilled amounts accounted for
     *         The loan is created on the loan offer's terms
     *
     * @param borrowRequest The borrow request to match
     * @param loanOffer The loan offer to match
     */
    function matchProposals(Proposal calldata borrowRequest, Proposal calldata loanOffer) external;

    /**
     * @notice Repay a loan. The loan must be repaid in entirety.
     *
     * @param loanId The loan ID to repay
     * @param maxRepaymentAmount The maximum repayment amount. If the transaction is pending for too long,
     *                           the debt might increase to a point where it no longer makese sense for the
     *                           borrower to repay the loan.
     */
    function repay(uint256 loanId, uint256 maxRepaymentAmount) external;

    /**
     * @notice Refinance a loan. Only callable by the borrower.
     *         The new lender must offer a rate better than the current rate.
     *
     *         A protocol fee is charged on top of the debt. If the borrower owes 100 USDB and the protocol fee % is 1%,
     *         the borrower receives 100 USDB, which is used to repay the old lender, and is charged 1.0101010101 USDB in protocol fee.
     *
     * @param refinancing The refinancing struct includes loanId, loan proposal, and signature
     */
    function refinance(Refinancing calldata refinancing) external;

    /**
     * @notice Refinance multiple loans at once. Only callable by the refinancer.
     *
     * @param refinancings Array of refinancing structs
     */
    function refinance(Refinancing[] calldata refinancings) external;

    /**
     * @notice Call a matured and unpaid loan. This triggers a Dutch auction.
     *
     * @param loanId The loan ID to call
     */
    function call(uint256 loanId) external;

    /**
     * @notice Bid on a called loan. The interest rate per second increases linearly with time
     *         since the loan was called. The maximum interest rate per second is 10,000% APY.
     *
     *         A protocol fee is charged on top of the debt. If the borrower owes 100 USDB and the protocol fee % is 1%,
     *         the borrower receives 100 USDB, which is used to repay the old lender, and is charged 1.0101010101 USDB in protocol fee.
     *
     * @param loanId The loan ID to auction
     * @param maxInterestRatePerSecond The maximum interest rate per second to bid at
     */
    function auction(uint256 loanId, uint256 maxInterestRatePerSecond) external;

    /**
     * @notice Default on a loan and transfer the collateral to the lender.
     *         This can only be called after the auction duration has passed.
     *
     * @param loanId The loan ID to default
     */
    function seize(uint256 loanId) external;

    /**
     * @notice Mark the provided salts as cancelled. This prevents proposals using these salts from being fulfilled.
     *
     * @param requests The requests to cancel
     */
    function cancel(SaltCancellationRequest[] calldata requests) external;

    /**
     * @notice Increment the caller's lending and borrowing nonces.
     *
     * @param lending Whether to increment the lending nonce
     * @param borrowing Whether to increment the borrowing nonce
     */
    function incrementNonces(bool lending, bool borrowing) external;

    /**
     * @notice Toggle the auto-refinancing preference for the caller.
     */
    function toggleAutoRefinancingEnabled() external;

    /**
     * @notice Calculate the current interest rate per second for an auction
     *
     * @param loanId The loan ID to auction
     *
     * @return currentInterestRatePerSecond The auction's current interest rate per second
     */
    function auctionCurrentInterestRatePerSecond(
        uint256 loanId
    ) external view returns (uint256 currentInterestRatePerSecond);

    /**
     * @notice Calculate the collateral amount required for a given loan fulfillment amount.
     *
     * @dev This function calculates the collateral amount required based on the proposal's terms and current fulfillment status
     *      Calling this function can also verify the fulfill amount's validity as it reverts if it's too high or too low.
     *
     * @param proposal The loan proposal containing the terms
     * @param fulfillAmount The loan amount to be fulfilled
     *
     * @return collateralAmountRequired The amount of collateral required for the given loan fulfillment amount
     */
    function calculateCollateralAmountRequired(
        Proposal calldata proposal,
        uint256 fulfillAmount
    ) external view returns (uint256 collateralAmountRequired);

    /**
     * @notice Calculate the amount owed on a loan
     *
     * @param loanId The loan ID to calculate the amount owed
     *
     * @return debt The principal plus interest owed
     */
    function calculateDebt(uint256 loanId) external view returns (uint256 debt);

    /**
     * @notice Get a proposal's fulfillment data
     *
     * @param proposal The proposal to get the fulfillment for
     *
     * @return proposalId The proposal's ID
     * @return collateralAmount The collateral amount depostied through the proposal so far
     * @return loanAmount The loan amount given out through the proposal so far
     */
    function getFulfillment(
        Proposal calldata proposal
    ) external view returns (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount);

    /**
     * @notice Hash a proposal and return the digest.
     *
     * @param proposal The proposal to hash
     *
     * @return digest The hashed proposal
     */
    function hashProposal(Proposal calldata proposal) external view returns (bytes32 digest);
}
