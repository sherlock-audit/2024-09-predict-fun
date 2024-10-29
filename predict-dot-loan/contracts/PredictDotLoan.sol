// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {InterestLib} from "./libraries/InterestLib.sol";
import {NegRiskIdLib} from "./libraries/NegRiskIdLib.sol";
import {CalculatorHelper} from "./libraries/CalculatorHelper.sol";
import {IConditionalTokens} from "./interfaces/IConditionalTokens.sol";
import {IPredictDotLoan} from "./interfaces/IPredictDotLoan.sol";
import {ICTFExchange, Order, Side} from "./interfaces/ICTFExchange.sol";
import {IUmaCtfAdapter} from "./interfaces/IUmaCtfAdapter.sol";
import {INegRiskAdapter} from "./interfaces/INegRiskAdapter.sol";
import {INegRiskOperator} from "./interfaces/INegRiskOperator.sol";

/**
 * @title PredictDotLoan
 * @notice PredictDotLoan matches lenders and borrowers
 *         of conditional tokens traded on predict.fun's CTF exchange.
 * @author predict.fun protocol team
 */
contract PredictDotLoan is AccessControl, EIP712, ERC1155Holder, IPredictDotLoan, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using InterestLib for uint256;

    /**
     * @notice Refinancers are allowed to refinance loans on behalf of borrowers.
     */
    bytes32 private constant REFINANCIER_ROLE = keccak256("REFINANCIER_ROLE");

    /**
     * @notice Proposals matcher is allowed to match proposals.
     */
    bytes32 private constant PROPOSALS_MATCHER_ROLE = keccak256("PROPOSALS_MATCHER_ROLE");

    /**
     * @notice Max interest rate per second is 10,000% APY
     */
    uint256 private constant MAX_INTEREST_RATE_PER_SECOND = InterestLib.ONE + InterestLib.TEN_THOUSAND_APY;

    /**
     * @notice Auction duration after a loan is called
     */
    uint256 private constant AUCTION_DURATION = 1 days;

    /**
     * @notice The maximum protocol fee is 2%
     */
    uint256 private constant MAXIMUM_PROTOCOL_FEE_BASIS_POINTS = 200;

    /**
     * @notice predict.fun CTF exchange
     */
    ICTFExchange public immutable CTF_EXCHANGE;

    /**
     * @notice predict.fun neg risk CTF exchange
     */
    ICTFExchange public immutable NEG_RISK_CTF_EXCHANGE;

    /**
     * @notice predict.fun The only loan token allowed is the CTF exchange's collateral
     */
    IERC20 private immutable LOAN_TOKEN;

    /**
     * @notice Conditional tokens that can be used as collateral
     */
    IConditionalTokens private immutable CTF;

    /**
     * @notice Binary outcome UMA CTF adapter
     */
    address public immutable UMA_CTF_ADAPTER;

    /**
     * @notice Neg risk UMA CTF adapter
     */
    address public immutable NEG_RISK_UMA_CTF_ADAPTER;

    /**
     * @notice Neg risk adapter
     */
    INegRiskAdapter private immutable NEG_RISK_ADAPTER;

    /**
     * @notice Neg risk operator
     */
    INegRiskOperator public immutable NEG_RISK_OPERATOR;

    /**
     * @notice Proposals can be partially fulfilled. This mapping keeps track of the proposal's fulfilled amount.
     *         The key is the hash of the user address, salt, and proposal type.
     */
    mapping(bytes32 key => Fulfillment) private fulfillments;

    /**
     * @notice Proposals can be cancelled. This mapping keeps track of a user's salts that have been cancelled.
     *         Each salt can be used for exactly one loan offer and one borrow request.
     *         Partially fulfilled salts can be cancelled but it does not affect already fulfilled amounts.
     */
    mapping(address user => mapping(uint256 salt => SaltCancellationStatus status)) public saltCancellations;

    /**
     * @notice Nonces are used to allow batch cancellations of loan offers and borrowing requests.
     */
    mapping(address user => Nonces) public nonces;

    /**
     * @notice Each loan has a unique ID. With each new loan created, this counter is incremented.
     */
    uint256 private nextLoanId = 1;

    mapping(uint256 loanId => Loan loan) public loans;

    /**
     * @notice positionQuestion keeps track of the association between a position and a question.
     *         Each position should belong to exactly one question, there cannot be two positions
     *         with the same ID that map to different questions
     */
    mapping(uint256 positionId => bytes32 questionId) private positionQuestion;

    /**
     * @notice Users who do not enable auto-refinancing will not have their loans auto-refinanced
     *         by a refinancier when there is a better loan offer available.
     */
    mapping(address user => uint256 enableAutoRefinancing) public autoRefinancingEnabled;

    /**
     * @notice The protocol charges a fee on each loan. The fee goes to this address.
     */
    address private protocolFeeRecipient;

    /**
     * @notice The protocol charges a fee on each loan. The fee is a percentage of the loan amount.
     */
    uint8 private protocolFeeBasisPoints;

    /**
     * @notice The minimum order fee rate for order fills. The difference between the order fee rate and the minimum order fee rate
     *         is refunded to the maker. It behaves similarly to the makerFeeRate in
     *         https://github.com/Polymarket/exchange-fee-module/blob/main/src/FeeModule.sol#L45.
     */
    uint16 private minimumOrderFeeRate;

    /**
     * @dev LOAN_TOKEN, CTF and NEG_RISK_ADAPTER are private. We have to lower the contract size
     *      and by having CTF_EXCHANGE and NEG_RISK_CTF_EXCHANGE as public, users can verify the
     *      these private variables from outside the contract.
     *
     *      protocolFeeRecipient, protocolFeeBasisPoints and minimumOrderFeeRate are private, but
     *      they can be accessed off-chain using `ethers.getStorageAt`.
     *
     * @param _owner Contract owner
     * @param _protocolFeeRecipient Protocol fee recipient
     * @param _ctfExchange predict.fun CTF exchange
     * @param _negRiskCtfExchange predict.fun neg risk CTF exchange
     * @param _umaCtfAdapter Binary outcome UMA CTF adapter
     * @param _negRiskUmaCtfAdapter Neg risk UMA CTF adapter
     * @param _negRiskOperator Neg risk operator
     */
    constructor(
        address _owner,
        address _protocolFeeRecipient,
        address _ctfExchange,
        address _negRiskCtfExchange,
        address _umaCtfAdapter,
        address _negRiskUmaCtfAdapter,
        address _negRiskOperator
    ) EIP712("predict.loan", "1") {
        CTF_EXCHANGE = ICTFExchange(_ctfExchange);
        NEG_RISK_CTF_EXCHANGE = ICTFExchange(_negRiskCtfExchange);

        LOAN_TOKEN = IERC20(CTF_EXCHANGE.getCollateral());
        if (address(LOAN_TOKEN) != NEG_RISK_CTF_EXCHANGE.getCollateral()) {
            revert OnlyOneLoanTokenAllowed();
        }

        UMA_CTF_ADAPTER = _umaCtfAdapter;
        NEG_RISK_UMA_CTF_ADAPTER = _negRiskUmaCtfAdapter;
        NEG_RISK_ADAPTER = INegRiskAdapter(NEG_RISK_CTF_EXCHANGE.getCtf());

        CTF = IConditionalTokens(CTF_EXCHANGE.getCtf());
        if (NEG_RISK_ADAPTER.ctf() != address(CTF)) {
            revert OnlyOneCTFAllowed();
        }

        NEG_RISK_OPERATOR = INegRiskOperator(_negRiskOperator);
        if (address(NEG_RISK_OPERATOR.nrAdapter()) != address(NEG_RISK_ADAPTER)) {
            revert InvalidNegRiskOperator();
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _updateProtocolFeeRecipient(_protocolFeeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                            KEY FLOW
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPredictDotLoan
     */
    function acceptBorrowRequest(
        Proposal calldata proposal,
        uint256 fulfillAmount
    ) external nonReentrant whenNotPaused {
        _assertProposalIsBorrowRequest(proposal);
        _acceptOffer(proposal, fulfillAmount);
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function acceptLoanOffer(Proposal calldata proposal, uint256 fulfillAmount) external nonReentrant whenNotPaused {
        _assertProposalIsLoanOffer(proposal);
        _acceptOffer(proposal, fulfillAmount);
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function acceptLoanOfferAndFillOrder(
        Order calldata exchangeOrder,
        Proposal calldata proposal
    ) external nonReentrant whenNotPaused {
        _assertProposalIsLoanOffer(proposal);

        uint256 positionId = _derivePositionId(proposal);
        if (exchangeOrder.tokenId != positionId) {
            revert PositionIdMismatch();
        }

        if (exchangeOrder.maker == proposal.from || exchangeOrder.maker == msg.sender) {
            revert SellerMustBeThirdParty();
        }

        if (exchangeOrder.side != Side.SELL) {
            revert NotSellOrder();
        }

        if (exchangeOrder.feeRateBps < minimumOrderFeeRate) {
            revert OrderFeeRateTooLow();
        }

        bytes32 proposalId = hashProposal(proposal);
        uint256 protocolFee = (exchangeOrder.takerAmount * proposal.protocolFeeBasisPoints) /
            (10_000 - proposal.protocolFeeBasisPoints);
        uint256 fulfillAmount = exchangeOrder.takerAmount + protocolFee;
        _assertProposalValidity(proposalId, proposal, positionId, fulfillAmount);

        Fulfillment storage fulfillment = _getFulfillment(proposal);
        uint256 collateralAmountRequired = _calculateCollateralAmountRequired(proposal, fulfillment, fulfillAmount);

        if (exchangeOrder.makerAmount < collateralAmountRequired) {
            revert InsufficientCollateral();
        }

        _updateFulfillment(fulfillment, collateralAmountRequired, fulfillAmount, proposalId);

        _transferLoanAmountAndProtocolFeeWithoutDeductingFromLoanAmount(
            proposal.from,
            address(this),
            exchangeOrder.takerAmount,
            protocolFee
        );

        uint256 collateralTokenBalance = _getPositionBalance(positionId);

        _fillOrder(exchangeOrder, _selectExchangeForQuestionType(proposal.questionType));

        {
            uint256 collateralTokenBalanceIncrease = _getPositionBalance(positionId) - collateralTokenBalance;

            if (collateralTokenBalanceIncrease < exchangeOrder.makerAmount) {
                revert OrderDidNotFill();
            }

            _transferExcessCollateralIfAny(
                positionId,
                msg.sender,
                collateralAmountRequired,
                collateralTokenBalanceIncrease
            );

            if (exchangeOrder.feeRateBps > minimumOrderFeeRate) {
                uint256 refund = CalculatorHelper.calcRefund(
                    exchangeOrder.feeRateBps,
                    minimumOrderFeeRate,
                    collateralTokenBalanceIncrease,
                    exchangeOrder.makerAmount,
                    exchangeOrder.takerAmount,
                    Side.SELL
                );

                _transferLoanToken(exchangeOrder.maker, refund);
            }

            uint256 protocolFeesNotRefunded = LOAN_TOKEN.balanceOf(address(this));
            if (protocolFeesNotRefunded > 0) {
                _transferLoanToken(protocolFeeRecipient, protocolFeesNotRefunded);
            }
        }

        _createLoan(
            nextLoanId,
            proposal,
            positionId,
            proposal.from,
            msg.sender,
            collateralAmountRequired,
            fulfillAmount
        );

        emit OrderFilledUsingProposal(
            proposalId,
            nextLoanId,
            msg.sender,
            proposal.from,
            positionId,
            collateralAmountRequired,
            fulfillAmount,
            protocolFee
        );

        unchecked {
            ++nextLoanId;
        }
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function matchProposals(
        Proposal calldata borrowRequest,
        Proposal calldata loanOffer
    ) external nonReentrant whenNotPaused {
        _assertProposalIsBorrowRequest(borrowRequest);
        _assertProposalIsLoanOffer(loanOffer);

        _assertLenderIsNotBorrower(loanOffer.from, borrowRequest.from);

        if (msg.sender != loanOffer.from && msg.sender != borrowRequest.from) {
            _checkRole(PROPOSALS_MATCHER_ROLE);
        }

        uint256 positionId = _derivePositionId(borrowRequest);
        // This also indirectly checks that the questionType is the same
        if (positionId != _derivePositionId(loanOffer)) {
            revert PositionIdMismatch();
        }

        _assertPositionTradeableOnExchange(positionId, borrowRequest.questionType);

        _assertValidInterestRatePerSecond(loanOffer.interestRatePerSecond);
        _assertValidInterestRatePerSecond(borrowRequest.interestRatePerSecond);

        if (borrowRequest.interestRatePerSecond < loanOffer.interestRatePerSecond) {
            revert UnacceptableInterestRatePerSecond();
        }

        if (borrowRequest.duration > loanOffer.duration) {
            revert UnacceptableDuration();
        }

        _assertCollateralizationRatioAtLeastOneHundredPercent(loanOffer.collateralAmount, loanOffer.loanAmount);
        _assertCollateralizationRatioAtLeastOneHundredPercent(borrowRequest.collateralAmount, borrowRequest.loanAmount);

        if (
            borrowRequest.collateralAmount * loanOffer.loanAmount <
            borrowRequest.loanAmount * loanOffer.collateralAmount
        ) {
            revert UnacceptableCollateralizationRatio();
        }

        _assertNotExpired(borrowRequest.validUntil);
        _assertNotExpired(loanOffer.validUntil);

        _assertMatchingProtocolFeeBasisPoints(loanOffer.protocolFeeBasisPoints);
        _assertMatchingProtocolFeeBasisPoints(borrowRequest.protocolFeeBasisPoints);

        bytes32 loanOfferProposalId = hashProposal(loanOffer);
        _assertValidSignature(loanOfferProposalId, loanOffer.from, loanOffer.signature);

        bytes32 borrowRequestProposalId = hashProposal(borrowRequest);
        _assertValidSignature(borrowRequestProposalId, borrowRequest.from, borrowRequest.signature);

        // To fix stack too deep when via-IR is turned off
        uint256 fulfillAmount;
        uint256 collateralAmountRequired;

        {
            Fulfillment storage loanOfferFulfillment = _getFulfillment(loanOffer);
            Fulfillment storage borrowRequestFulfillment = _getFulfillment(borrowRequest);

            _assertSaltNotUsedByAnotherProposal(borrowRequestFulfillment.proposalId, borrowRequestProposalId);
            _assertSaltNotUsedByAnotherProposal(loanOfferFulfillment.proposalId, loanOfferProposalId);

            uint256 loanOfferFulfilledAmount = loanOfferFulfillment.loanAmount;
            uint256 borrowRequestFulfilledAmount = borrowRequestFulfillment.loanAmount;

            uint256 loanOfferAvailableFulfillAmount = loanOffer.loanAmount - loanOfferFulfilledAmount;
            uint256 borrowRequestAvailableFulfillAmount = borrowRequest.loanAmount - borrowRequestFulfilledAmount;

            // No need to check _assertFulfillAmountNotTooHigh
            fulfillAmount = loanOfferAvailableFulfillAmount > borrowRequestAvailableFulfillAmount
                ? borrowRequestAvailableFulfillAmount
                : loanOfferAvailableFulfillAmount;

            _assertFulfillAmountNotTooLow(fulfillAmount, borrowRequestFulfilledAmount, borrowRequest.loanAmount);
            _assertFulfillAmountNotTooLow(fulfillAmount, loanOfferFulfilledAmount, loanOffer.loanAmount);

            collateralAmountRequired = _calculateCollateralAmountRequired(
                loanOffer,
                loanOfferFulfillment,
                fulfillAmount
            );

            // Even though the actual collateral amount required is calculated based on the loan offer,
            // the borrow request's fulfillment is updated with the collateral amount required
            // based on the borrow request to prevent the last loan to have a wildly different
            // collateral ratio
            _updateFulfillment(
                borrowRequestFulfillment,
                _calculateCollateralAmountRequired(borrowRequest, borrowRequestFulfillment, fulfillAmount),
                fulfillAmount,
                borrowRequestProposalId
            );
            _updateFulfillment(loanOfferFulfillment, collateralAmountRequired, fulfillAmount, loanOfferProposalId);
        }

        _assertProposalNotCancelled(borrowRequest.from, borrowRequest.salt, borrowRequest.proposalType);
        _assertProposalNotCancelled(loanOffer.from, loanOffer.salt, loanOffer.proposalType);

        _assertProposalNonceIsCurrent(loanOffer.proposalType, loanOffer.from, loanOffer.nonce);
        _assertProposalNonceIsCurrent(borrowRequest.proposalType, borrowRequest.from, borrowRequest.nonce);

        // Just need to check borrow request's question as the question is the same
        _assertQuestionPriceUnavailable(borrowRequest.questionType, borrowRequest.questionId);

        uint256 protocolFee = _transferLoanAmountAndProtocolFee(loanOffer.from, borrowRequest.from, fulfillAmount);

        _transferCollateralToken(borrowRequest.from, address(this), positionId, collateralAmountRequired);

        uint256 _nextLoanId = nextLoanId;
        _createLoan(
            _nextLoanId,
            loanOffer,
            positionId,
            loanOffer.from,
            borrowRequest.from,
            collateralAmountRequired,
            fulfillAmount
        );

        emit ProposalsMatched(
            loanOfferProposalId,
            borrowRequestProposalId,
            _nextLoanId,
            borrowRequest.from,
            loanOffer.from,
            positionId,
            collateralAmountRequired,
            fulfillAmount,
            protocolFee
        );

        unchecked {
            ++nextLoanId;
        }
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function repay(uint256 loanId, uint256 maxRepaymentAmount) external nonReentrant {
        Loan storage loan = loans[loanId];

        _assertAuthorizedCaller(loan.borrower);

        LoanStatus status = loan.status;
        if (status != LoanStatus.Active) {
            if (status != LoanStatus.Called) {
                revert InvalidLoanStatus();
            }
        }

        if (loan.startTime == block.timestamp) {
            revert LoanCannotBeRepaidInstantly();
        }

        uint256 debt = _calculateDebt(loan.loanAmount, loan.interestRatePerSecond, _calculateLoanTimeElapsed(loan));

        if (maxRepaymentAmount < debt) {
            revert MaxRepaymentAmountExceeded();
        }

        loan.status = LoanStatus.Repaid;

        _transferLoanTokenFrom(msg.sender, loan.lender, debt);
        _transferCollateralToken(address(this), msg.sender, loan.positionId, loan.collateralAmount);

        emit LoanRepaid(loanId, debt);
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function refinance(Refinancing calldata refinancing) external nonReentrant whenNotPaused {
        _assertAuthorizedCaller(loans[refinancing.loanId].borrower);

        (uint256 id, Loan memory loan, uint256 protocolFee) = _refinance(refinancing);

        emit LoanRefinanced(
            hashProposal(refinancing.proposal),
            refinancing.loanId,
            id,
            loan.lender,
            loan.collateralAmount,
            loan.loanAmount,
            loan.interestRatePerSecond,
            loan.minimumDuration,
            protocolFee
        );
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function refinance(
        Refinancing[] calldata refinancings
    ) external nonReentrant whenNotPaused onlyRole(REFINANCIER_ROLE) {
        RefinancingResult[] memory results = new RefinancingResult[](refinancings.length);
        for (uint256 i; i < refinancings.length; ++i) {
            Refinancing calldata refinancing = refinancings[i];
            (uint256 id, Loan memory loan, uint256 protocolFee) = _refinance(refinancing);

            // Doing this check after the refinancing, but in realitiy
            // it does not matter because the transaction simulation would've
            // failed before it is submitted on-chain.
            address borrower = loan.borrower;
            if (autoRefinancingEnabled[borrower] == 0) {
                revert BorrowerDidNotEnableAutoRefinancing(borrower);
            }

            results[i] = RefinancingResult(
                hashProposal(refinancing.proposal),
                refinancing.loanId,
                id,
                loan.lender,
                loan.collateralAmount,
                loan.loanAmount,
                loan.interestRatePerSecond,
                loan.minimumDuration,
                protocolFee
            );
        }
        emit LoansRefinanced(results);
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function call(uint256 loanId) external nonReentrant {
        Loan storage loan = loans[loanId];

        _assertAuthorizedCaller(loan.lender);
        _assertLoanStatus(loan.status, LoanStatus.Active);

        if (loan.startTime + loan.minimumDuration > block.timestamp) {
            revert LoanNotMatured();
        }

        if (
            _isQuestionPriceAvailable(loan.questionType, positionQuestion[loan.positionId]) ||
            _calculateDebt(loan.loanAmount, loan.interestRatePerSecond, _calculateLoanTimeElapsed(loan)) >
            loan.collateralAmount
        ) {
            _seize(loanId, loan);
        } else {
            loan.status = LoanStatus.Called;
            loan.callTime = block.timestamp;

            emit LoanCalled(loanId);
        }
    }

    /**
     * @inheritdoc IPredictDotLoan
     *
     * @dev Loans created via an auction does not have a minimum duration as the new lender is already
     *      taking a risk on a borrower who has a history of not repaying. The new lender is free to
     *      trigger an auction any time.
     */
    function auction(uint256 loanId, uint256 maxInterestRatePerSecond) external nonReentrant whenNotPaused {
        Loan storage loan = loans[loanId];

        _assertLoanStatus(loan.status, LoanStatus.Called);

        _assertLenderIsNotBorrower(msg.sender, loan.borrower);

        _assertNewLenderIsNotTheSameAsOldLender(msg.sender, loan.lender);

        uint256 callTime = loan.callTime;
        uint256 timeElapsed = block.timestamp - callTime;

        _assertAuctionIsActive(timeElapsed);

        uint256 positionId = loan.positionId;

        // If the question is resolved in the middle of the auction, the lender can wait for the auction to be over
        // and seize the collateral
        _assertQuestionPriceUnavailable(loan.questionType, positionQuestion[positionId]);

        uint256 interestRatePerSecond = _auctionCurrentInterestRatePerSecond(timeElapsed);

        if (interestRatePerSecond > maxInterestRatePerSecond) {
            revert InterestRatePerSecondTooHigh();
        }

        loan.status = LoanStatus.Auctioned;

        uint256 _nextLoanId = nextLoanId;
        uint256 debt = _calculateDebt(loan.loanAmount, loan.interestRatePerSecond, callTime - loan.startTime);
        uint256 protocolFee = (debt * protocolFeeBasisPoints) / (10_000 - protocolFeeBasisPoints);
        uint256 loanAmount = debt + protocolFee;
        uint256 collateralAmount = loan.collateralAmount;

        _assertCollateralizationRatioAtLeastOneHundredPercent(collateralAmount, loanAmount);

        Loan storage newLoan = loans[_nextLoanId];
        newLoan.borrower = loan.borrower;
        newLoan.lender = msg.sender;
        newLoan.positionId = positionId;
        newLoan.collateralAmount = collateralAmount;
        newLoan.loanAmount = loanAmount;
        newLoan.interestRatePerSecond = interestRatePerSecond;
        newLoan.startTime = block.timestamp;
        newLoan.status = LoanStatus.Active;
        newLoan.questionType = loan.questionType;

        _transferLoanAmountAndProtocolFeeWithoutDeductingFromLoanAmount(msg.sender, loan.lender, debt, protocolFee);

        unchecked {
            ++nextLoanId;
        }

        emit LoanTransferred(loanId, debt, protocolFee, _nextLoanId, msg.sender, interestRatePerSecond);
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function seize(uint256 loanId) external nonReentrant {
        Loan storage loan = loans[loanId];

        _assertAuthorizedCaller(loan.lender);
        _assertLoanStatus(loan.status, LoanStatus.Called);

        if (!_isQuestionPriceAvailable(loan.questionType, positionQuestion[loan.positionId])) {
            if (loan.callTime + AUCTION_DURATION >= block.timestamp) {
                revert AuctionNotOver();
            }
        }

        _seize(loanId, loan);
    }

    /*//////////////////////////////////////////////////////////////
                        CANCELLATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPredictDotLoan
     */
    function cancel(SaltCancellationRequest[] calldata requests) external {
        if (requests.length == 0) {
            revert NoSaltCancellationRequests();
        }

        for (uint256 i; i < requests.length; ++i) {
            SaltCancellationRequest calldata request = requests[i];
            uint256 salt = request.salt;
            SaltCancellationStatus storage status = saltCancellations[msg.sender][salt];

            if (!request.lending && !request.borrowing) {
                revert NotCancelling();
            }

            if (request.lending) {
                if (status.lending) {
                    revert SaltAlreadyCancelled(salt);
                }
                status.lending = true;
            }

            if (request.borrowing) {
                if (status.borrowing) {
                    revert SaltAlreadyCancelled(salt);
                }
                status.borrowing = true;
            }
        }

        emit SaltsCancelled(msg.sender, requests);
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function incrementNonces(bool lending, bool borrowing) external {
        if (!lending && !borrowing) {
            revert NotIncrementing();
        }

        uint128 lendingNonce = nonces[msg.sender].lending;
        uint128 borrowingNonce = nonces[msg.sender].borrowing;

        if (lending) {
            unchecked {
                nonces[msg.sender].lending = ++lendingNonce;
            }
        }

        if (borrowing) {
            unchecked {
                nonces[msg.sender].borrowing = ++borrowingNonce;
            }
        }

        emit NoncesIncremented(lendingNonce, borrowingNonce);
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function toggleAutoRefinancingEnabled() external nonReentrant {
        uint256 preference = autoRefinancingEnabled[msg.sender] == 0 ? 1 : 0;
        autoRefinancingEnabled[msg.sender] = preference;
        emit AutoRefinancingEnabledToggled(msg.sender, preference);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the minimum order fee rate. Only callable by admins.
     *
     * @dev predict.fun's max fee rate is 10% but we are not going to check it here.
     *      We can disable acceptLoanOfferAndFillOrder if needed by setting minimumOrderFeeRate
     *      to a value higher than 10%.
     *
     * @param _minimumOrderFeeRate The minimum order fee rate
     */
    function updateMinimumOrderFeeRate(uint16 _minimumOrderFeeRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minimumOrderFeeRate = _minimumOrderFeeRate;
        emit MinimumOrderFeeRateUpdated(_minimumOrderFeeRate);
    }

    /**
     * @notice Update the protocol fee basis points. Only callable by admins.
     *
     * @param _protocolFeeBasisPoints The protocol fee basis points
     */
    function updateProtocolFeeBasisPoints(uint8 _protocolFeeBasisPoints) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_protocolFeeBasisPoints > MAXIMUM_PROTOCOL_FEE_BASIS_POINTS) {
            revert ProtocolFeeBasisPointsTooHigh();
        }
        protocolFeeBasisPoints = _protocolFeeBasisPoints;
        emit ProtocolFeeBasisPointsUpdated(_protocolFeeBasisPoints);
    }

    /**
     * @notice When a contract is paused, no new loans including refinancing and auction can be created.
     *         All operations with existing loans still work.
     *         Only callable by admins.
     */
    function togglePaused() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused() ? _unpause() : _pause();
    }

    /**
     * @notice Update the protocol fee recipient. Only callable by admins.
     *
     * @param _protocolFeeRecipient The address of the protocol fee recipient
     */
    function updateProtocolFeeRecipient(address _protocolFeeRecipient) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateProtocolFeeRecipient(_protocolFeeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IPredictDotLoan
     */
    function auctionCurrentInterestRatePerSecond(
        uint256 loanId
    ) external view returns (uint256 currentInterestRatePerSecond) {
        Loan storage loan = loans[loanId];

        _assertLoanStatus(loan.status, LoanStatus.Called);

        uint256 timeElapsed = block.timestamp - loan.callTime;

        _assertAuctionIsActive(timeElapsed);

        currentInterestRatePerSecond = _auctionCurrentInterestRatePerSecond(timeElapsed);
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function calculateDebt(uint256 loanId) external view returns (uint256 debt) {
        Loan storage loan = loans[loanId];

        if (loan.status != LoanStatus.Active) {
            if (loan.status != LoanStatus.Called) {
                return 0;
            }
        }

        debt = _calculateDebt(loan.loanAmount, loan.interestRatePerSecond, _calculateLoanTimeElapsed(loan));
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function calculateCollateralAmountRequired(
        Proposal calldata proposal,
        uint256 fulfillAmount
    ) public view returns (uint256 collateralAmountRequired) {
        Fulfillment storage fulfillment = _getFulfillment(proposal);
        _assertFulfillAmountNotTooLow(fulfillAmount, fulfillment.loanAmount, proposal.loanAmount);
        _assertFulfillAmountNotTooHigh(fulfillAmount, fulfillment.loanAmount, proposal.loanAmount);
        collateralAmountRequired = _calculateCollateralAmountRequired(proposal, fulfillment, fulfillAmount);
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function getFulfillment(
        Proposal calldata proposal
    ) external view returns (bytes32 proposalId, uint256 collateralAmount, uint256 loanAmount) {
        Fulfillment storage fulfillment = _getFulfillment(proposal);
        proposalId = fulfillment.proposalId;
        collateralAmount = fulfillment.collateralAmount;
        loanAmount = fulfillment.loanAmount;
    }

    /**
     * @inheritdoc IPredictDotLoan
     */
    function hashProposal(Proposal calldata proposal) public view returns (bytes32 digest) {
        digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "Proposal("
                        "address from,"
                        "uint256 loanAmount,"
                        "uint256 collateralAmount,"
                        "uint8 questionType,"
                        "bytes32 questionId,"
                        "bool outcome,"
                        "uint256 interestRatePerSecond,"
                        "uint256 duration,"
                        "uint256 validUntil,"
                        "uint256 salt,"
                        "uint256 nonce,"
                        "uint8 proposalType,"
                        "uint256 protocolFeeBasisPoints"
                        ")"
                    ),
                    proposal.from,
                    proposal.loanAmount,
                    proposal.collateralAmount,
                    proposal.questionType,
                    proposal.questionId,
                    proposal.outcome,
                    proposal.interestRatePerSecond,
                    proposal.duration,
                    proposal.validUntil,
                    proposal.salt,
                    proposal.nonce,
                    proposal.proposalType,
                    proposal.protocolFeeBasisPoints
                )
            )
        );
    }

    /**
     * @notice Query if a contract implements an interface
     *
     * @param interfaceId The interface identifier, as specified in ERC-165
     *
     * @return `true` if the contract implements `interfaceId` and `interfaceId` is not 0xffffffff, `false` otherwise
     */
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC1155Holder) returns (bool) {
        return
            interfaceId == type(AccessControl).interfaceId ||
            interfaceId == type(ERC1155Holder).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        _assertTokenReceivedIsCTF();
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        _assertTokenReceivedIsCTF();
        return this.onERC1155BatchReceived.selector;
    }

    /*//////////////////////////////////////////////////////////////
                    LOAN TOKEN TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    function _seize(uint256 loanId, Loan storage loan) private {
        loan.status = LoanStatus.Defaulted;

        _transferCollateralToken(address(this), msg.sender, loan.positionId, loan.collateralAmount);

        emit LoanDefaulted(loanId);
    }

    /**
     * @dev Transfer loan amount from one address to another.
     *      If the protocol fee is greater than 0, deduct the protocol fee from the loan amount.
     */
    function _transferLoanAmountAndProtocolFee(
        address from,
        address to,
        uint256 loanAmount
    ) private returns (uint256 protocolFee) {
        protocolFee = (loanAmount * protocolFeeBasisPoints) / 10_000;
        _transferLoanTokenFrom(from, to, loanAmount - protocolFee);
        if (protocolFee > 0) {
            _transferLoanTokenFrom(from, protocolFeeRecipient, protocolFee);
        }
    }

    /**
     * @dev Transfer loan amount from one address to another.
     *      If the protocol fee is greater than 0, do not deduct the protocol fee from the loan amount.
     *      The protocol fee is on top of the loan amount.
     */
    function _transferLoanAmountAndProtocolFeeWithoutDeductingFromLoanAmount(
        address from,
        address to,
        uint256 loanAmount,
        uint256 protocolFee
    ) private {
        _transferLoanTokenFrom(from, to, loanAmount);
        if (protocolFee > 0) {
            _transferLoanTokenFrom(from, protocolFeeRecipient, protocolFee);
        }
    }

    function _transferExcessCollateralIfAny(
        uint256 positionId,
        address receiver,
        uint256 collateralAmountRequired,
        uint256 actualCollateralAmount
    ) private {
        uint256 excessCollateral = actualCollateralAmount - collateralAmountRequired;

        if (excessCollateral > 0) {
            _transferCollateralToken(address(this), receiver, positionId, excessCollateral);
        }
    }

    function _transferCollateralToken(address from, address to, uint256 positionId, uint256 amount) private {
        CTF.safeTransferFrom(from, to, positionId, amount, "");
    }

    function _transferLoanToken(address to, uint256 amount) private {
        LOAN_TOKEN.safeTransfer(to, amount);
    }

    function _transferLoanTokenFrom(address from, address to, uint256 amount) private {
        LOAN_TOKEN.safeTransferFrom(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                    EXCHANGE ORDER FULFILLMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _fillOrder(Order calldata exchangeOrder, ICTFExchange exchange) private {
        LOAN_TOKEN.safeIncreaseAllowance(address(exchange), exchangeOrder.takerAmount);
        exchange.fillOrder(exchangeOrder, exchangeOrder.makerAmount);
        LOAN_TOKEN.forceApprove(address(exchange), 0);
    }

    function _selectExchangeForQuestionType(QuestionType questionType) private view returns (ICTFExchange exchange) {
        exchange = questionType == QuestionType.Binary ? CTF_EXCHANGE : NEG_RISK_CTF_EXCHANGE;
    }

    /*//////////////////////////////////////////////////////////////
                       FULFILLMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev The unique key is created by hashing a user's address, salt, and proposal type.
     */
    function _getFulfillment(Proposal calldata proposal) private view returns (Fulfillment storage fulfillment) {
        fulfillment = fulfillments[keccak256(abi.encodePacked(proposal.from, proposal.salt, proposal.proposalType))];
    }

    /**
     * @dev Keep track of a proposal's collateral taken and loan amount given out so far.
     */
    function _updateFulfillment(
        Fulfillment storage fulfillment,
        uint256 collateralAmountRequired,
        uint256 fulfillAmount,
        bytes32 proposalId
    ) private {
        fulfillment.collateralAmount += collateralAmountRequired;
        fulfillment.loanAmount += fulfillAmount;
        if (fulfillment.proposalId == bytes32(0)) {
            fulfillment.proposalId = proposalId;
        }
    }

    /*//////////////////////////////////////////////////////////////
                       CREATE LOAN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _acceptOffer(Proposal calldata proposal, uint256 fulfillAmount) private {
        bytes32 proposalId = hashProposal(proposal);
        uint256 positionId = _derivePositionId(proposal);

        _assertProposalValidity(proposalId, proposal, positionId, fulfillAmount);

        Fulfillment storage fulfillment = _getFulfillment(proposal);
        uint256 collateralAmountRequired = _calculateCollateralAmountRequired(proposal, fulfillment, fulfillAmount);

        _updateFulfillment(fulfillment, collateralAmountRequired, fulfillAmount, proposalId);

        address from = proposal.from;
        address lender = proposal.proposalType == ProposalType.LoanOffer ? from : msg.sender;
        address borrower = lender == msg.sender ? from : msg.sender;

        uint256 protocolFee = _transferLoanAmountAndProtocolFee(lender, borrower, fulfillAmount);
        _transferCollateralToken(borrower, address(this), positionId, collateralAmountRequired);

        _createLoan(nextLoanId, proposal, positionId, lender, borrower, collateralAmountRequired, fulfillAmount);

        emit ProposalAccepted(
            nextLoanId,
            proposalId,
            borrower,
            lender,
            positionId,
            collateralAmountRequired,
            fulfillAmount,
            protocolFee
        );

        unchecked {
            ++nextLoanId;
        }
    }

    function _createLoan(
        uint256 id,
        Proposal calldata proposal,
        uint256 positionId,
        address lender,
        address borrower,
        uint256 collateralAmount,
        uint256 loanAmount
    ) private {
        loans[id].lender = lender;
        loans[id].borrower = borrower;
        loans[id].positionId = positionId;
        loans[id].collateralAmount = collateralAmount;
        loans[id].loanAmount = loanAmount;
        loans[id].interestRatePerSecond = proposal.interestRatePerSecond;
        loans[id].startTime = block.timestamp;
        loans[id].minimumDuration = proposal.duration;
        loans[id].status = LoanStatus.Active;
        loans[id].questionType = proposal.questionType;

        if (positionQuestion[positionId] == bytes32(0)) {
            positionQuestion[positionId] = proposal.questionId;
        }
    }

    /**
     * @dev Refinance a loan. The function is used by both the borrower initiated refinancing
     *      and auto-refinancing.
     *
     * @dev There is no need to check the position is tradeable on the exchange because it has already been
     *      checked when the loan was first created and it is not possible to de-register a token on the exchange.
     *
     * @param refinancing The refinancing struct contains loanId, loan proposal and signature
     *
     * @return id The new loan's ID
     * @return newLoan The new loan
     * @return protocolFee The protocol fee charged for the refinancing
     */
    function _refinance(
        Refinancing calldata refinancing
    ) private returns (uint256 id, Loan memory newLoan, uint256 protocolFee) {
        Proposal calldata proposal = refinancing.proposal;
        _assertProposalIsLoanOffer(proposal);

        Loan storage loan = loans[refinancing.loanId];

        _assertLoanStatus(loan.status, LoanStatus.Active);

        address borrower = loan.borrower;
        address lender = proposal.from;
        _assertLenderIsNotBorrower(borrower, lender);

        _assertNewLenderIsNotTheSameAsOldLender(lender, loan.lender);

        _assertNotExpired(proposal.validUntil);

        _assertMatchingProtocolFeeBasisPoints(proposal.protocolFeeBasisPoints);

        if (msg.sender != borrower) {
            if (loan.startTime + loan.minimumDuration > block.timestamp + proposal.duration) {
                revert UnexpectedDurationShortening();
            }
        }

        uint256 positionId = _derivePositionId(proposal);
        if (positionId != loan.positionId) {
            revert PositionIdMismatch();
        }

        _assertQuestionPriceUnavailable(proposal.questionType, proposal.questionId);

        _assertValidInterestRatePerSecond(proposal.interestRatePerSecond);

        if (proposal.interestRatePerSecond > loan.interestRatePerSecond) {
            revert WorseInterestRatePerSecond();
        }

        bytes32 proposalId = hashProposal(proposal);
        _assertValidSignature(proposalId, lender, proposal.signature);

        Fulfillment storage fulfillment = _getFulfillment(proposal);

        uint256 debt = _calculateDebt(loan.loanAmount, loan.interestRatePerSecond, block.timestamp - loan.startTime);
        protocolFee = (debt * proposal.protocolFeeBasisPoints) / (10_000 - proposal.protocolFeeBasisPoints);
        uint256 fulfillAmount = debt + protocolFee;
        _assertFulfillAmountNotTooLow(fulfillAmount, fulfillment.loanAmount, proposal.loanAmount);

        _assertProposalNotCancelled(lender, proposal.salt, proposal.proposalType);

        _assertSaltNotUsedByAnotherProposal(fulfillment.proposalId, proposalId);

        _assertProposalNonceIsCurrent(proposal.proposalType, lender, proposal.nonce);

        _assertFulfillAmountNotTooHigh(fulfillAmount, fulfillment.loanAmount, proposal.loanAmount);

        uint256 collateralAmountRequired = _calculateCollateralAmountRequired(proposal, fulfillment, fulfillAmount);

        _assertCollateralizationRatioAtLeastOneHundredPercent(collateralAmountRequired, fulfillAmount);

        if (collateralAmountRequired > loan.collateralAmount) {
            revert InsufficientCollateral();
        }

        loan.status = LoanStatus.Refinanced;

        _updateFulfillment(fulfillment, collateralAmountRequired, fulfillAmount, proposalId);

        _transferLoanAmountAndProtocolFeeWithoutDeductingFromLoanAmount(lender, loan.lender, debt, protocolFee);

        _transferExcessCollateralIfAny(positionId, borrower, collateralAmountRequired, loan.collateralAmount);

        id = nextLoanId;

        _createLoan(id, proposal, positionId, proposal.from, borrower, collateralAmountRequired, fulfillAmount);

        newLoan = loans[id];

        unchecked {
            ++nextLoanId;
        }
    }

    /*//////////////////////////////////////////////////////////////
                    VARIOUS CALCULATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @param timeElapsed The time elapsed since the loan was called
     *
     * @return currentInterestRatePerSecond The current interest rate per second in the specified auction
     */
    function _auctionCurrentInterestRatePerSecond(
        uint256 timeElapsed
    ) private pure returns (uint256 currentInterestRatePerSecond) {
        currentInterestRatePerSecond =
            InterestLib.ONE +
            (timeElapsed * InterestLib.TEN_THOUSAND_APY) /
            AUCTION_DURATION;
    }

    /**
     * @dev Calculate the collateral amount required to fulfill a loan offer or a borrow request
     *      If the fulfill amount is equal to the remaining fulfill amount, the collateral amount required
     *      is equal to the proposal's collateral amount - the fulfillment's collateral amount so far.
     *
     * @param proposal The proposal
     * @param fulfillment The proposal's fulfillment so far
     * @param fulfillAmount The loan amount to fulfill
     *
     * @return collateralAmountRequired The collateral amount required to fulfill the loan offer or borrow request
     */
    function _calculateCollateralAmountRequired(
        Proposal calldata proposal,
        Fulfillment storage fulfillment,
        uint256 fulfillAmount
    ) private view returns (uint256 collateralAmountRequired) {
        if (fulfillment.loanAmount + fulfillAmount == proposal.loanAmount) {
            collateralAmountRequired = proposal.collateralAmount - fulfillment.collateralAmount;
        } else {
            collateralAmountRequired = (proposal.collateralAmount * fulfillAmount) / proposal.loanAmount;
        }
    }

    /**
     * @dev Calculate the amount owed on a loan
     *
     * @param loanAmount The loan's principal amount
     * @param interestRatePerSecond The loan's interest rate per second
     * @param timeElapsed The time elapsed on the loan so far
     *
     * @return debt The principal plus interest owed
     */
    function _calculateDebt(
        uint256 loanAmount,
        uint256 interestRatePerSecond,
        uint256 timeElapsed
    ) private pure returns (uint256 debt) {
        debt = (loanAmount * interestRatePerSecond.pow(timeElapsed)) / InterestLib.ONE;
    }

    /**
     * @dev Calculate the time elapsed for a loan.
     *      If the loan has not been called, the time elapsed is the time since the loan was created.
     *      If the loan has been called, the time elapsed stops at the call time. Once the auction starts
     *      the timer stops to prevent the debt from increasing.
     *
     * @param loan The loan to calculate the time elapsed
     *
     * @return timeElapsed The time elapsed since the loan was created
     */
    function _calculateLoanTimeElapsed(Loan storage loan) private view returns (uint256 timeElapsed) {
        uint256 endTime = loan.callTime == 0 ? block.timestamp : loan.callTime;
        unchecked {
            timeElapsed = endTime - loan.startTime;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function _assertAuctionIsActive(uint256 timeElapsed) private pure {
        if (timeElapsed == 0) {
            revert AuctionNotStarted();
        }

        if (timeElapsed > AUCTION_DURATION) {
            revert AuctionIsOver();
        }
    }

    function _assertAuthorizedCaller(address authorizedCaller) private view {
        if (authorizedCaller != msg.sender) {
            revert UnauthorizedCaller();
        }
    }

    /**
     * @dev Collateralization ratio must be at least 100%.
     *      Revert if the collateral amount is less than the loan amount.
     *
     * @param collateralAmount The proposal's collateral amount
     * @param loanAmount The proposal's loan amount
     */
    function _assertCollateralizationRatioAtLeastOneHundredPercent(
        uint256 collateralAmount,
        uint256 loanAmount
    ) private pure {
        if (collateralAmount < loanAmount) {
            revert CollateralizationRatioTooLow();
        }
    }

    function _assertLenderIsNotBorrower(address userOne, address userTwo) private pure {
        if (userOne == userTwo) {
            revert LenderIsBorrower();
        }
    }

    function _assertMatchingProtocolFeeBasisPoints(uint256 proposalProtocolFeeBasisPoints) private view {
        if (proposalProtocolFeeBasisPoints != protocolFeeBasisPoints) {
            revert ProtocolFeeBasisPointsMismatch();
        }
    }

    function _assertNewLenderIsNotTheSameAsOldLender(address newLender, address oldLender) private pure {
        if (newLender == oldLender) {
            revert NewLenderIsTheSameAsOldLender();
        }
    }

    /**
     * @dev We want to ensure each fulfillment is at least 10% of the loan amount
     *      to prevent too many small loans from being created. It would be detrimental
     *      to user experience.
     *
     *      If the remaining loan amount is less than 10% of the loan amount, we allow the fulfillment to be smaller than 10%
     *      but the loan has to be fully fulfilled.
     */
    function _assertFulfillAmountNotTooLow(
        uint256 fulfillAmount,
        uint256 fulfilledAmount,
        uint256 loanAmount
    ) private pure {
        if (fulfillAmount == 0) {
            revert FulfillAmountTooLow();
        }

        if (fulfillAmount != loanAmount - fulfilledAmount) {
            if (fulfillAmount < loanAmount / 10) {
                revert FulfillAmountTooLow();
            }
        }
    }

    function _assertFulfillAmountNotTooHigh(
        uint256 fulfillAmount,
        uint256 fulfilledAmount,
        uint256 loanAmount
    ) private pure {
        if (fulfilledAmount + fulfillAmount > loanAmount) {
            revert FulfillAmountTooHigh();
        }
    }

    function _assertLoanStatus(LoanStatus status, LoanStatus expectedStatus) private pure {
        if (status != expectedStatus) {
            revert InvalidLoanStatus();
        }
    }

    function _assertProposalNonceIsCurrent(ProposalType proposalType, address from, uint256 nonce) private view {
        Nonces storage userNonces = nonces[from];
        if (proposalType == ProposalType.LoanOffer) {
            if (nonce != userNonces.lending) {
                revert InvalidNonce();
            }
        } else {
            if (nonce != userNonces.borrowing) {
                revert InvalidNonce();
            }
        }
    }

    function _assertNotExpired(uint256 validUntil) private view {
        if (block.timestamp > validUntil) {
            revert Expired();
        }
    }

    /**
     * @dev Position must be tradeable on the exchange or the neg risk CTF exchange
     *
     * @param positionId The position ID derived from the user's question ID and outcome
     * @param questionType The question type provided by the user
     */
    function _assertPositionTradeableOnExchange(uint256 positionId, QuestionType questionType) private view {
        (uint256 complement, ) = _selectExchangeForQuestionType(questionType).registry(positionId);
        if (complement == 0) {
            revert PositionIdNotTradeableOnExchange();
        }
    }

    function _assertProposalIsBorrowRequest(Proposal calldata proposal) private pure {
        if (proposal.proposalType != ProposalType.BorrowRequest) {
            revert NotBorrowRequest();
        }
    }

    function _assertProposalIsLoanOffer(Proposal calldata proposal) private pure {
        if (proposal.proposalType != ProposalType.LoanOffer) {
            revert NotLoanOffer();
        }
    }

    function _assertProposalNotCancelled(address user, uint256 salt, ProposalType proposalType) private view {
        SaltCancellationStatus storage status = saltCancellations[user][salt];

        if (proposalType == ProposalType.LoanOffer) {
            if (status.lending) {
                revert ProposalCancelled();
            }
        } else {
            if (status.borrowing) {
                revert ProposalCancelled();
            }
        }
    }

    function _assertSaltNotUsedByAnotherProposal(bytes32 fulfillmentProposalId, bytes32 proposalId) private pure {
        if (fulfillmentProposalId != bytes32(0)) {
            if (fulfillmentProposalId != proposalId) {
                revert SaltAlreadyUsed();
            }
        }
    }

    function _assertTokenReceivedIsCTF() private view {
        if (msg.sender != address(CTF)) {
            revert ContractOnlyAcceptsCTF();
        }
    }

    /**
     * @dev Interest rate per second must be greater than 1e18 or else debt will not increase over time
     */
    function _assertValidInterestRatePerSecond(uint256 interestRatePerSecond) private pure {
        if (interestRatePerSecond <= InterestLib.ONE) {
            revert InterestRatePerSecondTooLow();
        }

        if (interestRatePerSecond > MAX_INTEREST_RATE_PER_SECOND) {
            revert InterestRatePerSecondTooHigh();
        }
    }

    /**
     * @dev The protocol supports both EOA and EIP-1271 signatures
     */
    function _assertValidSignature(bytes32 proposalId, address from, bytes calldata signature) private view {
        if (!SignatureChecker.isValidSignatureNow(from, proposalId, signature)) {
            revert InvalidSignature();
        }
    }

    /**
     * @dev Shared validation logic between loan offers and borrow requests.
     *
     * @param proposalId The proposal's hash
     * @param proposal The proposal to accept
     * @param positionId The position ID derived from the proposal's question ID, collateral token and outcome
     * @param fulfillAmount Loan amount to fulfill
     */
    function _assertProposalValidity(
        bytes32 proposalId,
        Proposal calldata proposal,
        uint256 positionId,
        uint256 fulfillAmount
    ) private view {
        _assertNotExpired(proposal.validUntil);

        address signer = proposal.from;
        _assertLenderIsNotBorrower(signer, msg.sender);
        _assertValidSignature(proposalId, signer, proposal.signature);

        Fulfillment storage fulfillment = _getFulfillment(proposal);

        uint256 loanAmount = proposal.loanAmount;
        _assertFulfillAmountNotTooLow(fulfillAmount, fulfillment.loanAmount, loanAmount);

        _assertProposalNotCancelled(signer, proposal.salt, proposal.proposalType);

        _assertSaltNotUsedByAnotherProposal(fulfillment.proposalId, proposalId);

        _assertProposalNonceIsCurrent(proposal.proposalType, proposal.from, proposal.nonce);

        _assertFulfillAmountNotTooHigh(fulfillAmount, fulfillment.loanAmount, loanAmount);

        _assertCollateralizationRatioAtLeastOneHundredPercent(proposal.collateralAmount, loanAmount);

        _assertValidInterestRatePerSecond(proposal.interestRatePerSecond);

        _assertPositionTradeableOnExchange(positionId, proposal.questionType);
        _assertQuestionPriceUnavailable(proposal.questionType, proposal.questionId);

        _assertMatchingProtocolFeeBasisPoints(proposal.protocolFeeBasisPoints);
    }

    /*//////////////////////////////////////////////////////////////
                        UMA/NEG RISK LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev This function is only meant to be called by _assertQuestionPriceUnavailable(QuestionType,bytes32)
     */
    function _assertBinaryOutcomeQuestionPriceUnavailable(address umaCtfAdapter, bytes32 questionId) private view {
        (bool isAvailable, bytes4 umaError) = _isBinaryOutcomeQuestionPriceAvailable(umaCtfAdapter, questionId);

        // 0x579a4801 is the error code for PriceNotAvailable()
        if (isAvailable) {
            revert QuestionResolved();
        } else if (umaError != 0x579a4801) {
            // Loans should still be blocked if the error is NotInitialized, Flagged, Paused or InvalidOOPrice
            // Reference: https://github.com/Polymarket/uma-ctf-adapter/blob/main/src/UmaCtfAdapter.sol#L145
            revert AbnormalQuestionState();
        }
    }

    /**
     * @dev We do not allow positions that are already resolved from being used as collaterals for loans
     *      as it is very likely that the position is worth nothing
     */
    function _assertQuestionPriceUnavailable(QuestionType questionType, bytes32 questionId) private view {
        if (questionType == QuestionType.Binary) {
            _assertBinaryOutcomeQuestionPriceUnavailable(UMA_CTF_ADAPTER, questionId);
        } else {
            if (_isNegRiskMarketDetermined(questionId)) {
                revert MarketResolved();
            }

            _assertBinaryOutcomeQuestionPriceUnavailable(NEG_RISK_UMA_CTF_ADAPTER, questionId);
        }
    }

    /**
     * @dev Neg risk adapter does not use the UMA question ID to determine if the market is resolved.
     *      If uses the market ID which is derived from a different question ID. This question ID has
     *      its last 8 bit masked and replaced with the question's index under the market.
     *
     * @param oracleRequestId The oracle request ID is the neg risk question ID
     */
    function _isNegRiskMarketDetermined(bytes32 oracleRequestId) private view returns (bool isDetermined) {
        bytes32 questionId = NEG_RISK_OPERATOR.questionIds(oracleRequestId);
        if (questionId == bytes32(0)) {
            revert NoQuestionIdForOracleRequestId();
        }
        isDetermined = NEG_RISK_ADAPTER.getDetermined(NegRiskIdLib.getMarketId(questionId));
    }

    function _isBinaryOutcomeQuestionPriceAvailable(
        address umaCtfAdapter,
        bytes32 questionId
    ) private view returns (bool isAvailable, bytes4 umaError) {
        try IUmaCtfAdapter(umaCtfAdapter).getExpectedPayouts(questionId) returns (uint256[] memory) {
            isAvailable = true;
        } catch (bytes memory reason) {
            isAvailable = false;
            umaError = bytes4(reason);
        }
    }

    /**
     * @dev The price availability check for neg risk questions here is different from _assertQuestionPriceUnavailable.
     *      Here we only check the market is determined and we don't check if the price is available on UMA CTF adapter.
     *      We should keep the UMA price check for _assertQuestionPriceUnavailable to block loans from being created if
     *      the question is resolved on UMA CTF adapter (even if it's not final). We don't do the check here to make sure
     *      the lenders cannot seize the collateral until the market's resolution is finalized. Not even the contract owner
     *      can modify the result by calling NegRiskOperator.resolveQuestion.
     */
    function _isQuestionPriceAvailable(
        QuestionType questionType,
        bytes32 questionId
    ) private view returns (bool isAvailable) {
        if (questionType == QuestionType.Binary) {
            (isAvailable, ) = _isBinaryOutcomeQuestionPriceAvailable(UMA_CTF_ADAPTER, questionId);
        } else {
            isAvailable = _isNegRiskMarketDetermined(questionId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        PROTOCOL FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    function _updateProtocolFeeRecipient(address _protocolFeeRecipient) private {
        if (_protocolFeeRecipient == address(0)) {
            revert ZeroAddress();
        }
        protocolFeeRecipient = _protocolFeeRecipient;
        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                        CONDITIONAL TOKENS LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Derive the position ID from the question type, question ID and outcome
     *
     *      The proposal struct does not require positionId directly because it has
     *      to verify the question ID is not already resolved and the position ID actually
     *      comes from the question ID provided. It is more efficient to just derive the
     *      position ID and use it instead of requiring the user to provide it and then
     *      compare it to the derived position ID.
     */
    function _derivePositionId(Proposal calldata proposal) private view returns (uint256 positionId) {
        if (proposal.questionType == QuestionType.Binary) {
            bytes32 conditionId = _getConditionId(UMA_CTF_ADAPTER, proposal.questionId, 2);
            bytes32 collectionId = CTF.getCollectionId(bytes32(0), conditionId, proposal.outcome ? 1 : 2);
            positionId = _getPositionId(LOAN_TOKEN, collectionId);
        } else {
            positionId = NEG_RISK_ADAPTER.getPositionId(proposal.questionId, proposal.outcome);
        }
    }

    function _getPositionBalance(uint256 positionId) private view returns (uint256 balance) {
        balance = CTF.balanceOf(address(this), positionId);
    }

    /*//////////////////////////////////////////////////////////////
          LOGIC COPIED FROM CTHelpers FOR PERFORMANCE REASONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Constructs a condition ID from an oracle, a question ID, and the outcome slot count for the question.
    /// @param oracle The account assigned to report the result for the prepared condition.
    /// @param questionId An identifier for the question to be answered by the oracle.
    /// @param outcomeSlotCount The number of outcome slots which should be used for this condition. Must not exceed 256.
    function _getConditionId(address oracle, bytes32 questionId, uint outcomeSlotCount) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(oracle, questionId, outcomeSlotCount));
    }

    /// @dev Constructs a position ID from a collateral token and an outcome collection. These IDs are used as the ERC-1155 ID for this contract.
    /// @param collateralToken Collateral token which backs the position.
    /// @param collectionId ID of the outcome collection associated with this position.
    function _getPositionId(IERC20 collateralToken, bytes32 collectionId) private pure returns (uint) {
        return uint(keccak256(abi.encodePacked(collateralToken, collectionId)));
    }
}
