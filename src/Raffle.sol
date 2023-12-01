//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title Etherquino - Raffle Contract
/// @author Numa
/// @notice We'll create a sample raffle
/// @dev Implements Chainlink VRFv2

// import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
//import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

//FIX REMAPPING
import {VRFCoordinatorV2Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    /* Type declarations */
    enum RaffleState {
        OPEN, //0
        CALCULATING //1
    }

    /* State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    /// @dev duration of the lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint64 private immutable i_subscriptionId;

    address payable[] private s_players;
    uint256 private s_lastTimestamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /* Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 _entranceFee,
        uint256 _interval,
        address _vrfCoordinator,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        i_entranceFee = _entranceFee;
        i_interval = _interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        i_gasLane = _gasLane;
        i_subscriptionId = _subscriptionId;
        i_callbackGasLimit = _callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimestamp = block.timestamp;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not Enough ETH");
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);
    }

    /// @notice This is the function that the Chainlink Automation nodes call to see if it's time to perform an upkeep.
    /// The following should be true for this to return true:
    /// 1. The time interval has passed between raffle runs
    /// 2. Raffle is in OPEN state
    /// 3. Contract has ETH (aka players)
    /// 4. The subscription is funded with link
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimestamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    /// @notice if checkUpkeep() returns TRUE, this function is triggered by Chainlink nodes,
    /// which will perform a request to the Chainlink VRF. It will return a number and a winner will be selected.
    function performUpkeep(bytes calldata /* preformData */) external {
        (bool upkeepNeeded, ) = checkUpkeep((""));
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, //gas lane
            i_subscriptionId, //id funded w/LINK
            REQUEST_CONFIRMATIONS, //block confirmation
            i_callbackGasLimit,
            NUM_WORDS //number of random numbers
        );

        // @audit-issue redundant. requestRandomWords already emits an event
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*_requestId*/,
        uint256[] memory _randomWords
    ) internal override {
        uint256 indexOfWinner = _randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        s_players = new address payable[](0);
        s_lastTimestamp = block.timestamp;

        emit PickedWinner(winner);

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Functions */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }

    function getGasLane() external view returns (bytes32) {
        return i_gasLane;
    }

    function getCallbackGasLimit() external view returns (uint32) {
        return i_callbackGasLimit;
    }

    function getSubscriptionId() external view returns (uint64) {
        return i_subscriptionId;
    }

    function getLastTimestamp() external view returns (uint256) {
        return s_lastTimestamp;
    }

    /// @notice this will reset after the raffle
    function getPlayers() external view returns (address payable[] memory) {
        return s_players;
    }

    function getLastWinner() external view returns (address) {
        return s_recentWinner;
    }
}
