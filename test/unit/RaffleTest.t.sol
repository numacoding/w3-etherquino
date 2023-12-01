//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
// import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

import {VRFCoordinatorV2Mock} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /* Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed player);

    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant INITIAL_BALANCE = 10 ether;

    function setUp() external {
        vm.deal(PLAYER, INITIAL_BALANCE);
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();

        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);

        uint256 initialPlayers = raffle.getPlayers().length;
        raffle.enterRaffle{value: entranceFee}();

        assertEq(raffle.getPlayers().length, (initialPlayers + 1));
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating()
        public
        raffleEnteredAndTimePassed
    {
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert (not false)
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen()
        public
        raffleEnteredAndTimePassed
    {
        raffle.performUpkeep("");

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert (not false)
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert (not false)
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood()
        public
        raffleEnteredAndTimePassed
    {
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert (not false)
        assert(upkeepNeeded);
    }

    /* performUpkeep */
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue()
        public
        raffleEnteredAndTimePassed
    {
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertIfCheckUpkeepIsFalse() public {
        uint256 balance = 0;
        uint256 playersLength = 0;
        uint256 raffleState = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                balance,
                playersLength,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        vm.recordLogs(); //records the logs generated after this function is called
        raffle.performUpkeep(""); //emit requestid
        Vm.Log[] memory entries = vm.getRecordedLogs(); // collects the recorded logs emitted
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }

    /* fulfillRandomWords */

    // @audit fuzz test
    function testFulfullRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEnteredAndTimePassed skipFork {
        vm.expectRevert("nonexistent request");
        // @note we can impersonate the VRFCoordinator contract in Anvil, but not in another testnet/mainnet
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTimePassed
        skipFork
    {
        //1 enter the lottery
        //2 move the time up so checkUpkeep returns true
        //3 performUpkeep and kick off a request to get a random number
        //4 pretend to be the Chainlink VRF respond and call fulfillRandomWords
        uint256 additionalEntrants = 10;
        uint256 startingIndex = 1;

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, INITIAL_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        vm.recordLogs();
        raffle.performUpkeep(""); //emit requestid
        Vm.Log[] memory entries = vm.getRecordedLogs(); // collects the recorded logs emitted
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimestamp = raffle.getLastTimestamp();

        // uint256 prize = address(raffle).balance;
        // @note if I define the prize condition like that, I assume that no balance will remain
        // in the contract after the number is selected. This SHOULD be true, but we need to test that also.
        // For that reason, we calculate the prize like this:
        uint256 prize = entranceFee * (additionalEntrants + 1);

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getLastWinner() != address(0));
        assert(raffle.getPlayers().length == 0);
        assert(previousTimestamp < raffle.getLastTimestamp());
        assert(
            raffle.getLastWinner().balance ==
                INITIAL_BALANCE + prize - entranceFee
        );
    }

    /* Modifiers */

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }
}
