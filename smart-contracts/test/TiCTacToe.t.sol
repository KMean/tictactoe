// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicTacToe.sol";

/**
 * High‑level integration tests that exercise the full public surface of the
 * game contract.  Adjusted to the *new* fee‑flow: the 2 % dev‑fee is *only*
 * accumulated at game‑end and must be withdrawn later by the receiver.
 */

contract Receiver {
        receive() external payable {}
    }

contract DevReceiver {
    receive() external payable {}
}

contract TicTacToeTest is Test {
    /* ---------------------------------------------------------------------- */
    /*  Test scaffolding                                                      */
    /* ---------------------------------------------------------------------- */
    

    TicTacToe   public game;
    Receiver    public r1;
    Receiver    public r2;
    DevReceiver public dr;

    address public player1;
    address public player2;
    address public dev;

    function setUp() public {
        r1 = new Receiver();
        r2 = new Receiver();
        dr = new DevReceiver();

        player1 = address(r1);
        player2 = address(r2);
        dev     = address(dr);

        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);
        vm.deal(dev,     0);

        game = new TicTacToe(payable(dev));
    }

    /* ---------------------------------------------------------------------- */
    /*  Core flows                                                            */
    /* ---------------------------------------------------------------------- */

    function testGameFlow_WinByPlayer1() public {
        uint256 bet   = 0.02 ether;
        uint256 total = bet * 2;
        uint256 fee   = (total * 2) / 100;   // 2 %
        uint256 payout= total - fee;

        uint256 before = player1.balance;

        // create + join
        vm.prank(player1);
        uint256 id = game.createGame{value: bet}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: bet}(id);

        // left‑column win for X (player1)
        vm.prank(player1); game.makeMove(id, 0, 0);
        vm.prank(player2); game.makeMove(id, 1, 0);
        vm.prank(player1); game.makeMove(id, 0, 1);
        vm.prank(player2); game.makeMove(id, 1, 1);
        vm.prank(player1); game.makeMove(id, 0, 2);

        // balances *immediately* after win (fee is NOT sent yet)
        assertEq(player1.balance, before - bet + payout, "wrong winner balance");
        assertEq(player2.balance, 1 ether - bet,        "wrong loser balance");
        assertEq(dev.balance,      0,                   "fee should be accumulated only");

        // dev pulls the fee
        vm.prank(dev);
        game.withdrawDevFees();
        assertEq(dev.balance, fee, "dev did not receive accumulated fee");
    }

    function testGameDraw() public {
        vm.prank(player1);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: 0.1 ether}(id);

        // predetermined draw sequence
        vm.prank(player1); game.makeMove(id, 0, 0);
        vm.prank(player2); game.makeMove(id, 1, 1);
        vm.prank(player1); game.makeMove(id, 0, 1);
        vm.prank(player2); game.makeMove(id, 0, 2);
        vm.prank(player1); game.makeMove(id, 2, 0);
        vm.prank(player2); game.makeMove(id, 1, 0);
        vm.prank(player1); game.makeMove(id, 1, 2);
        vm.prank(player2); game.makeMove(id, 2, 1);
        vm.prank(player1); game.makeMove(id, 2, 2);

        TicTacToe.Game memory g = game.getGameState(id);
        assertEq(uint8(g.state), uint8(TicTacToe.GameState.Finished));
        assertEq(player1.balance, 1 ether);
        assertEq(player2.balance, 1 ether);
        assertEq(dev.balance,     0);
    }

    /* ---------------------------------------------------------------------- */
    /*  Smaller unit‑style checks                                             */
    /* ---------------------------------------------------------------------- */

    function testGetBoardState() public {
        vm.prank(player1);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: 0.1 ether}(id);
        vm.prank(player1);
        game.makeMove(id, 1, 1);

        TicTacToe.Player[9] memory board = game.getBoardState(id);
        assertEq(uint8(board[4]), uint8(TicTacToe.Player.X));
    }

    function testJoinGameMustMatchBet() public {
        vm.prank(player1);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(player2);
        vm.expectRevert(TicTacToe.MustMatchBet.selector);
        game.joinGame{value: 0.05 ether}(id);
    }

    function testCannotJoinOwnGame() public {
        vm.prank(player1);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(player1);
        vm.expectRevert(TicTacToe.CannotJoinOwnGame.selector);
        game.joinGame{value: 0.1 ether}(id);
    }

    function testCancelGame() public {
        vm.prank(player1);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(player1);
        game.cancelGame(id);

        TicTacToe.Game memory g = game.getGameState(id);
        assertEq(uint8(g.state), uint8(TicTacToe.GameState.Canceled));
        assertEq(player1.balance, 1 ether);
    }

    function testInvalidMoveOutOfBounds() public {
        vm.prank(player1);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: 0.1 ether}(id);

        vm.prank(player1);
        vm.expectRevert(TicTacToe.OutOfBounds.selector);
        game.makeMove(id, 3, 0);
    }

    function testInvalidMoveWrongTurn() public {
        vm.prank(player1);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: 0.1 ether}(id);

        vm.prank(player2);
        vm.expectRevert(TicTacToe.NotYourTurn.selector);
        game.makeMove(id, 0, 0);
    }

    function testWinByTimeout() public {
        uint256 bet   = 0.02 ether;
        uint256 total = bet * 2;
        uint256 fee   = (total * 2) / 100;
        uint256 payout= total - fee;

        uint256 before = player1.balance;

        vm.prank(player1);
        uint256 id = game.createGame{value: bet}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: bet}(id);

        vm.prank(player1);
        game.makeMove(id, 0, 0);

        vm.warp(block.timestamp + game.timeoutPeriod() + 1);

        vm.prank(player1);
        game.claimWinByTimeout(id);

        assertEq(player1.balance, before - bet + payout);
        assertEq(dev.balance,     0);

        // dev pulls fee
        vm.prank(dev);
        game.withdrawDevFees();
        assertEq(dev.balance, fee);
    }

    function testOnlyDevCanChangeTimeout() public {
        vm.prank(player1);
        vm.expectRevert(TicTacToe.NotAuthorized.selector);
        game.setTimeoutPeriod(100);

        vm.prank(dev);
        game.setTimeoutPeriod(100);
        assertEq(game.timeoutPeriod(), 100);
    }

    function testWithdrawDevFeesOnlyDev() public {
        // generate a game with fee
        uint256 bet = 0.05 ether;
        vm.prank(player1);
        uint256 id = game.createGame{value: bet}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: bet}(id);
        vm.prank(player1); game.makeMove(id, 0, 0);
        vm.prank(player2); game.makeMove(id, 1, 0);
        vm.prank(player1); game.makeMove(id, 0, 1);
        vm.prank(player2); game.makeMove(id, 1, 1);
        vm.prank(player1); game.makeMove(id, 0, 2); // win

        uint256 fee = (bet * 2 * 2) / 100;

        vm.prank(dev);
        game.withdrawDevFees();
        assertEq(dev.balance, fee);
    }

    function testWithdrawDevFeesNotDev() public {
        vm.prank(player1);
        vm.expectRevert(TicTacToe.NotAuthorized.selector);
        game.withdrawDevFees();
    }

    /* ---------------------------------------------------------------------- */
    /*  View helpers                                                          */
    /* ---------------------------------------------------------------------- */

    function testSecondsUntilTimeoutHelpers() public {
        vm.prank(player1);
        uint256 id = game.createGame{value: 0.01 ether}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: 0.01 ether}(id);

        uint256 left = game.getSecondsUntilTimeout(id);
        assertLe(left, game.timeoutPeriod());
        assertGt(left, 0);

        vm.warp(block.timestamp + game.timeoutPeriod() + 1);
        assertEq(game.getSecondsUntilTimeout(id), 0);
    }

    function testIsPlayerHelpers() public {
        vm.prank(player1);
        uint256 id = game.createGame{value: 0.01 ether}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: 0.01 ether}(id);

        assertTrue(game.isPlayer(id, player1));
        assertTrue(game.isPlayer(id, player2));
        assertFalse(game.isPlayer(id, address(0xdeadbeef)));
    }

    function testGetLeaderboardInitiallyZero() public view{
        TicTacToe.Stats memory s = game.getLeaderboard(player1);
        assertEq(s.wins,   0);
        assertEq(s.losses, 0);
        assertEq(s.draws,  0);
    }

    function testGetGameMeta() public {
        vm.prank(player1);
        uint256 id = game.createGame{value: 0.01 ether}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: 0.01 ether}(id);

        (
            address _c,
            address _o,
            TicTacToe.Player _cs,
            TicTacToe.Player _turn,
            uint256 _bet,
            TicTacToe.GameState _state,
            address _winner,
            uint256 _lt
        ) = game.getGameMeta(id);

        _turn == TicTacToe.Player.X ? TicTacToe.Player.X : TicTacToe.Player.O;
        assertEq(_c, player1);
        assertEq(_o, player2);
        assertEq(uint8(_cs), uint8(TicTacToe.Player.X));
        assertEq(_bet, 0.01 ether);
        assertEq(uint8(_state), uint8(TicTacToe.GameState.InProgress));
        assertEq(_winner, address(0));
        assertGt(_lt, 0);
    }

    
}
