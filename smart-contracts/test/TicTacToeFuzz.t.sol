// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicTacToe.sol";

contract Receiver {
    receive() external payable {}
}

contract TicTacToeFullFuzz is Test {
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

        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(dev, 0);

        game = new TicTacToe(dev);
    }

    function testFuzz_MoveOnce(uint8 x, uint8 y) public {
        x = x % 3;
        y = y % 3;

        vm.prank(player1);
        uint256 gameId = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(player2);
        game.joinGame{value: 0.1 ether}(gameId);

        vm.prank(player1);
        game.makeMove(gameId, x, y);

        vm.prank(player2);
        vm.expectRevert(TicTacToe.CellTaken.selector);
        game.makeMove(gameId, x, y);
    }

    function testFuzz_OutOfBounds(uint8 x, uint8 y) public {
        x = (x % 3) + 3;
        y = (y % 3) + 3;

        vm.prank(player1);
        uint256 gameId = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(player2);
        game.joinGame{value: 0.1 ether}(gameId);

        vm.prank(player1);
        vm.expectRevert(TicTacToe.OutOfBounds.selector);
        game.makeMove(gameId, x, y);
    }

    function testFuzz_InvalidJoinBet(uint256 fuzzBet) public {
        fuzzBet = bound(fuzzBet, 0.01 ether, 1 ether);
        vm.assume(fuzzBet != 0.1 ether);

        vm.prank(player1);
        uint256 gameId = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(player2);
        vm.expectRevert(TicTacToe.MustMatchBet.selector);
        game.joinGame{value: fuzzBet}(gameId);
    }

    function testFuzz_CompleteGameWithRandomPaths(
        uint8[9] calldata moves,
        uint8 cancelAfter,
        uint8 timeoutAfter,
        bool creatorStarts
    ) public {
        vm.prank(player1);
        uint256 gameId = game.createGame{value: 0.1 ether}(creatorStarts ? TicTacToe.Player.X : TicTacToe.Player.O);

        if (cancelAfter == 0) {
            vm.prank(player1);
            game.cancelGame(gameId);
            TicTacToe.Game memory g0 = game.getGameState(gameId);
            assertEq(uint8(g0.state), uint8(TicTacToe.GameState.Canceled));
            return;
        }

        vm.prank(player2);
        game.joinGame{value: 0.1 ether}(gameId);

        bool[3][3] memory played;

        for (uint8 i = 0; i < 9; i++) {
            uint8 move = moves[i] % 9;
            uint8 x = move / 3;
            uint8 y = move % 3;

            if (played[x][y]) continue;

            if (i == timeoutAfter) {
                address currentTurn = getCurrentPlayer(gameId);
                address other = currentTurn == player1 ? player2 : player1;

                vm.warp(block.timestamp + game.timeoutPeriod() + 1);
                vm.prank(other);
                try game.claimWinByTimeout(gameId) {} catch {}
                TicTacToe.Game memory g1 = game.getGameState(gameId);
                assertEq(uint8(g1.state), uint8(TicTacToe.GameState.Finished));
                return;
            }

            address current = (creatorStarts ? i % 2 == 0 : i % 2 != 0) ? player1 : player2;

            vm.prank(current);
            try game.makeMove(gameId, x, y) {
                played[x][y] = true;
                TicTacToe.Game memory g2 = game.getGameState(gameId);
                if (g2.state == TicTacToe.GameState.Finished) return;
            } catch {
                break;
            }

            if (i == cancelAfter) {
                vm.prank(player1);
                try game.cancelGame(gameId) {} catch {}
                return;
            }
        }

        TicTacToe.Game memory g = game.getGameState(gameId);
        assertTrue(g.state == TicTacToe.GameState.Finished || g.state == TicTacToe.GameState.InProgress);
    }

    function getCurrentPlayer(uint256 gameId) internal view returns (address) {
        TicTacToe.Game memory g = game.getGameState(gameId);
        return g.turn == g.creatorSymbol ? g.creator : g.opponent;
    }
}