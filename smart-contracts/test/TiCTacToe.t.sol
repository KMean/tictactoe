// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicTacToe.sol";

contract Receiver {
    receive() external payable {}
}

contract TicTacToeTest is Test {
    TicTacToe public game;
    Receiver public r1;
    Receiver public r2;
    address public player1;
    address public player2;
    address public dev = address(0xDEAD);

    function setUp() public {
        r1 = new Receiver();
        r2 = new Receiver();
        player1 = address(r1);
        player2 = address(r2);

        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);
        vm.deal(dev, 0);

        game = new TicTacToe(dev);
    }

    function testGameFlow_WinByPlayer1() public {
        uint256 bet = 0.02 ether;
        uint256 total = bet * 2;
        uint256 fee = (total * 2) / 100;
        uint256 expectedPayout = total - fee;

        uint256 before = player1.balance;

        vm.prank(player1);
        uint256 gameId = game.createGame{value: bet}(TicTacToe.Player.X);

        vm.prank(player2);
        game.joinGame{value: bet}(gameId);

        vm.prank(player1); game.makeMove(gameId, 0, 0);
        vm.prank(player2); game.makeMove(gameId, 1, 0);
        vm.prank(player1); game.makeMove(gameId, 0, 1);
        vm.prank(player2); game.makeMove(gameId, 1, 1);
        vm.prank(player1); game.makeMove(gameId, 0, 2); // Player 1 wins

        assertEq(player1.balance, before - bet + expectedPayout);
    }




    function testGameDraw() public {
        vm.prank(player1);
        uint256 gameId = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: 0.1 ether}(gameId);

        vm.prank(player1); game.makeMove(gameId, 0, 0);
        vm.prank(player2); game.makeMove(gameId, 1, 1);
        vm.prank(player1); game.makeMove(gameId, 0, 1);
        vm.prank(player2); game.makeMove(gameId, 0, 2);
        vm.prank(player1); game.makeMove(gameId, 2, 0);
        vm.prank(player2); game.makeMove(gameId, 1, 0);
        vm.prank(player1); game.makeMove(gameId, 1, 2);
        vm.prank(player2); game.makeMove(gameId, 2, 1);
        vm.prank(player1); game.makeMove(gameId, 2, 2);

        (, , , , , TicTacToe.GameState state, , ) = game.games(gameId);
        assertEq(uint8(state), uint8(TicTacToe.GameState.Finished));
        assertEq(player1.balance, 1 ether);
        assertEq(player2.balance, 1 ether);
        assertEq(dev.balance, 0);
    }

    function testJoinGameMustMatchBet() public {
        vm.prank(player1);
        uint256 gameId = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(player2);
        vm.expectRevert(TicTacToe.MustMatchBet.selector);
        game.joinGame{value: 0.05 ether}(gameId);
    }

    function testCannotJoinOwnGame() public {
        vm.prank(player1);
        uint256 gameId = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(player1);
        vm.expectRevert(TicTacToe.CannotJoinOwnGame.selector);
        game.joinGame{value: 0.1 ether}(gameId);
    }

    function testCancelGame() public {
        vm.prank(player1);
        uint256 gameId = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(player1);
        game.cancelGame(gameId);

        (, , , , , TicTacToe.GameState state, , ) = game.games(gameId);
        assertEq(uint8(state), uint8(TicTacToe.GameState.Canceled));
        assertEq(player1.balance, 1 ether);
    }

    function testInvalidMoveOutOfBounds() public {
        vm.prank(player1);
        uint256 gameId = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: 0.1 ether}(gameId);

        vm.prank(player1);
        vm.expectRevert(TicTacToe.OutOfBounds.selector);
        game.makeMove(gameId, 3, 0);
    }

    function testInvalidMoveWrongTurn() public {
        vm.prank(player1);
        uint256 gameId = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(player2);
        game.joinGame{value: 0.1 ether}(gameId);

        vm.prank(player2);
        vm.expectRevert(TicTacToe.NotYourTurn.selector);
        game.makeMove(gameId, 0, 0);
    }

    function testWinByTimeout() public {
        uint256 bet = 0.02 ether;
        uint256 total = bet * 2;
        uint256 fee = (total * 2) / 100;
        uint256 expectedPayout = total - fee;

        uint256 before = player1.balance;

        vm.prank(player1);
        uint256 gameId = game.createGame{value: bet}(TicTacToe.Player.X);

        vm.prank(player2);
        game.joinGame{value: bet}(gameId);

        vm.prank(player1);
        game.makeMove(gameId, 0, 0); // X moves

        // Simulate timeout
        vm.warp(block.timestamp + game.timeoutPeriod() + 1);

        vm.prank(player1);
        game.claimWinByTimeout(gameId);

        assertEq(player1.balance, before - bet + expectedPayout);
    }

    function testOnlyDevCanChangeTimeout() public {
        vm.prank(player1);
        vm.expectRevert(TicTacToe.NotAuthorized.selector);
        game.setTimeoutPeriod(100);

        vm.prank(dev);
        game.setTimeoutPeriod(100);
        assertEq(game.timeoutPeriod(), 100);
    }
}
