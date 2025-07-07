// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/TicTacToe.sol";

contract RevertingReceiver {
    fallback() external payable { revert("nope"); }
}

event GameCanceled(uint256 indexed id);

contract TicTacToeBranchCoverage is Test {
    receive() external payable {} // Accept ETH (acts as devFeeReceiver)

    TicTacToe public game;
    TicTacToe public gameWithBadDev;
    RevertingReceiver public badDev;

    address public creator;
    address public opponent;
    address public outsider;

    function setUp() public {
        creator  = makeAddr("creator");
        opponent = makeAddr("opponent");
        outsider = makeAddr("outsider");

        vm.deal(creator, 1 ether);
        vm.deal(opponent, 1 ether);
        vm.deal(outsider, 1 ether);

        game = new TicTacToe(payable(address(this)));
        badDev = new RevertingReceiver();
        gameWithBadDev = new TicTacToe(payable(address(badDev)));
    }

    function testWithdrawDevFees_Success() public {
        uint id = _createAndWin(game);
        console.log(id);
        uint256 before = address(this).balance;
        game.withdrawDevFees();
        uint256 expected = (2 * 0.1 ether * 2) / 100;
        assertEq(address(this).balance, before + expected);
    }

    function testWithdrawDevFees_TransferFailed() public {
        uint id = _createAndWin(gameWithBadDev);
        console.log(id);
        vm.prank(address(badDev));
        vm.expectRevert(TicTacToe.TransferFailed.selector);
        gameWithBadDev.withdrawDevFees();
    }

    function testGetBoardState_OwnedCellsMarkedCorrectly() public {
        uint id = _createAndJoin();
        vm.prank(creator); game.makeMove(id, 0, 0);
        vm.prank(opponent); game.makeMove(id, 1, 0);

        TicTacToe.Player[9] memory board = game.getBoardState(id);
        assertEq(uint8(board[0]), uint8(TicTacToe.Player.X));
        assertEq(uint8(board[1]), uint8(TicTacToe.Player.O));
    }

    function testMakeMove_RevertsIfCallerNotPlayer() public {
        uint id = _createAndJoin();
        vm.prank(outsider);
        vm.expectRevert(TicTacToe.NotAPlayer.selector);
        game.makeMove(id, 0, 0);
    }

    function testMakeMove_RevertsIfGameNotActive() public {
        uint id = _createAndJoin();
        vm.prank(creator); game.makeMove(id, 0, 0);
        vm.prank(opponent); game.makeMove(id, 1, 0);
        vm.prank(creator); game.makeMove(id, 0, 1);
        vm.prank(opponent); game.makeMove(id, 1, 1);
        vm.prank(creator); game.makeMove(id, 0, 2); // win
        vm.prank(opponent);
        vm.expectRevert(TicTacToe.GameNotActive.selector);
        game.makeMove(id, 2, 2);
    }

    function testSetTimeoutPeriod_UnauthorizedReverts() public {
        vm.prank(outsider);
        vm.expectRevert(TicTacToe.NotAuthorized.selector);
        game.setTimeoutPeriod(60);
    }

    function testGetGameMeta_RevertsIfGameMissing() public {
        vm.expectRevert(TicTacToe.GameDoesNotExist.selector);
        game.getGameMeta(999);
    }

    function testGetBoardState_RevertsIfGameMissing() public {
        vm.expectRevert(TicTacToe.GameDoesNotExist.selector);
        game.getBoardState(999);
    }

    function testIsPlayer_RevertsIfGameMissing() public {
        vm.expectRevert(TicTacToe.GameDoesNotExist.selector);
        game.isPlayer(999, address(0));
    }

    function testGetSecondsUntilTimeout_RevertsIfGameMissing() public {
        vm.expectRevert(TicTacToe.GameDoesNotExist.selector);
        game.getSecondsUntilTimeout(999);
    }

    function testClaimWinByTimeout_RevertsIfGameMissing() public {
        vm.expectRevert(TicTacToe.GameDoesNotExist.selector);
        game.claimWinByTimeout(999);
    }

    function testClaimWinByTimeout_RevertsIfNotTimedOut() public {
        uint id = _createAndJoin();
        vm.prank(opponent);
        vm.expectRevert(TicTacToe.TimeoutNotReached.selector);
        game.claimWinByTimeout(id);
    }

    function testJoinGame_RevertsIfAlreadyJoined() public {
        uint id = _createAndJoin();
        vm.prank(outsider);
        vm.expectRevert(TicTacToe.NotJoinable.selector);
        game.joinGame{value: 0.1 ether}(id);
    }

    function testCreateGame_RevertsIfSymbolNone() public {
        vm.prank(creator);
        vm.expectRevert(TicTacToe.InvalidSymbol.selector);
        game.createGame{value: 0.1 ether}(TicTacToe.Player.None);
    }

    function testWin_TopRow() public {
        uint id = _createAndJoin();
        vm.prank(creator); game.makeMove(id, 0, 0);
        vm.prank(opponent); game.makeMove(id, 0, 1);
        vm.prank(creator); game.makeMove(id, 1, 0);
        vm.prank(opponent); game.makeMove(id, 1, 1);
        vm.prank(creator); game.makeMove(id, 2, 0);
        assertEq(game.getGameState(id).winner, creator);
    }

    function testWin_EachWinningMask() public {
        uint8[3][8] memory patterns = [
            [uint8(0),1,2], [3,4,5], [6,7,8],     // Rows
            [0,3,6], [1,4,7], [2,5,8],           // Columns
            [0,4,8], [2,4,6]                     // Diagonals
        ];

        for (uint i = 0; i < patterns.length; ++i) {
            uint id = _createAndJoin();
            uint8[3] memory win = patterns[i];
            bool[9] memory used;

            for (uint j = 0; j < 3; ++j) used[win[j]] = true;

            for (uint j = 0; j < 3; ++j) {
                vm.prank(creator);
                game.makeMove(id, win[j] % 3, win[j] / 3);

                if (j < 2) {
                    for (uint8 k = 0; k < 9; ++k) {
                        if (!used[k]) {
                            vm.prank(opponent);
                            game.makeMove(id, k % 3, k / 3);
                            used[k] = true;
                            break;
                        }
                    }
                }
            }

            assertEq(game.getGameState(id).winner, creator, string(abi.encodePacked("Failed pattern ", vm.toString(i))));
        }
    }

    function _createAndJoin() internal returns (uint id) {
        vm.prank(creator);
        id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(opponent);
        game.joinGame{value: 0.1 ether}(id);
    }

    function _createAndWin(TicTacToe target) internal returns (uint id) {
        vm.prank(creator);
        id = target.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(opponent);
        target.joinGame{value: 0.1 ether}(id);
        vm.prank(creator);  target.makeMove(id, 0, 0);
        vm.prank(opponent); target.makeMove(id, 1, 0);
        vm.prank(creator);  target.makeMove(id, 0, 1);
        vm.prank(opponent); target.makeMove(id, 1, 1);
        vm.prank(creator);  target.makeMove(id, 0, 2);
    }

    function testClaimWinByTimeout_RevertsIfYouMustMove() public {
        uint256 id = _createAndJoin();

        // Make first move by creator (X), then opponent (O)
        vm.prank(creator);
        game.makeMove(id, 0, 0);

        vm.prank(opponent);
        game.makeMove(id, 1, 0);

        // It's now creator's turn (X), so if creator tries to timeout, it should revert
        vm.warp(block.timestamp + game.timeoutPeriod() + 1);

        vm.prank(creator);
        vm.expectRevert(TicTacToe.YouMustMove.selector);
        game.claimWinByTimeout(id);
    }

    function testFinishGameWithWinner_SafeSendFails() public {
        RevertingReceiver bad = new RevertingReceiver();
        vm.deal(address(bad), 0.1 ether);

        // bad is the creator
        vm.prank(address(bad));
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(opponent);
        game.joinGame{value: 0.1 ether}(id);

        // make bad win
        vm.prank(address(bad)); game.makeMove(id, 0, 0);
        vm.prank(opponent);     game.makeMove(id, 1, 0);
        vm.prank(address(bad)); game.makeMove(id, 0, 1);
        vm.prank(opponent);     game.makeMove(id, 1, 1);
        vm.prank(address(bad));
        vm.expectRevert(TicTacToe.TransferFailed.selector);
        game.makeMove(id, 0, 2);
    }
    
    function testFinishGameWithDraw_SafeSendFails() public {
        RevertingReceiver bad = new RevertingReceiver();
        vm.deal(address(bad), 0.1 ether);

        // bad = creator, r2 = opponent
        vm.prank(address(bad));
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(opponent);
        game.joinGame{value: 0.1 ether}(id);

        // Sequence leading to draw
        vm.prank(address(bad)); game.makeMove(id, 0, 0);
        vm.prank(opponent);      game.makeMove(id, 1, 1);
        vm.prank(address(bad)); game.makeMove(id, 0, 1);
        vm.prank(opponent);      game.makeMove(id, 0, 2);
        vm.prank(address(bad)); game.makeMove(id, 2, 0);
        vm.prank(opponent);      game.makeMove(id, 1, 0);
        vm.prank(address(bad)); game.makeMove(id, 1, 2);
        vm.prank(opponent);      game.makeMove(id, 2, 1);

        // Final move causes draw but creator (bad) will reject ETH
        vm.prank(address(bad));
        vm.expectRevert(TicTacToe.TransferFailed.selector);
        game.makeMove(id, 2, 2);
    }

    function testCancelGame_RevertsWithNotAuthorized() public {
        // Creator makes game
        vm.prank(creator);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        // Outsider tries to cancel
        vm.prank(outsider);
        vm.expectRevert(TicTacToe.NotAuthorized.selector);
        game.cancelGame(id);
    }

    function testCancelGame_RevertsIfAlreadyJoined() public {
        uint256 id = _createAndJoin();
        vm.prank(creator);
        vm.expectRevert(TicTacToe.CannotCancel.selector);
        game.cancelGame(id);
    }

    function testMakeMove_RevertsIfCellTaken() public {
        uint id = _createAndJoin();
        vm.prank(creator); game.makeMove(id, 0, 0);
        vm.prank(opponent);
        vm.expectRevert(TicTacToe.CellTaken.selector);
        game.makeMove(id, 0, 0);
    }

    function testClaimWinByTimeout_WorksForOpponent() public {
        uint256 id = _createAndJoin();

        vm.prank(creator);
        game.makeMove(id, 0, 0);

        vm.prank(opponent);
        game.makeMove(id, 1, 0);

        vm.warp(block.timestamp + game.timeoutPeriod() + 1);

        vm.prank(opponent);
        game.claimWinByTimeout(id);

        (,,,,,,,,address payable winner,) = game.games(id);
        assertEq(winner, opponent);

    }

    function testMakeMove_RevertsIfCellAlreadyTaken() public {
        uint256 id = _createAndJoin();
        vm.prank(creator);
        game.makeMove(id, 0, 0); // First move

        vm.prank(opponent);
        vm.expectRevert(TicTacToe.CellTaken.selector);
        game.makeMove(id, 0, 0); // Second move same cell
    }

    function testClaimWinByTimeout_RevertsIfGameFinished() public {
        uint256 id = _createAndJoin();
        // Finish the game
        vm.prank(creator); game.makeMove(id, 0, 0);
        vm.prank(opponent); game.makeMove(id, 1, 0);
        vm.prank(creator); game.makeMove(id, 0, 1);
        vm.prank(opponent); game.makeMove(id, 1, 1);
        vm.prank(creator); game.makeMove(id, 0, 2); // Win

        vm.warp(block.timestamp + game.timeoutPeriod() + 1);
        vm.prank(opponent);
        vm.expectRevert(TicTacToe.GameNotActive.selector);
        game.claimWinByTimeout(id);
    }

    function testClaimWinByTimeout_RevertsIfNotPlayer() public {
        uint256 id = _createAndJoin();

        // Skip timeout to avoid hitting TimeoutNotReached first
        vm.warp(block.timestamp + game.timeoutPeriod() + 1);

        vm.prank(outsider);
        vm.expectRevert(TicTacToe.NotAPlayer.selector);
        game.claimWinByTimeout(id);
    }


    function testClaimWinByTimeout_RevertsIfStillInTime() public {
        uint256 id = _createAndJoin();
        vm.prank(creator); game.makeMove(id, 0, 0);
        vm.prank(opponent); game.makeMove(id, 1, 0);

        vm.warp(block.timestamp + game.timeoutPeriod() - 5);
        vm.prank(opponent);
        vm.expectRevert(TicTacToe.TimeoutNotReached.selector);
        game.claimWinByTimeout(id);
    }

    function testClaimWinByTimeout_RevertsIfGameCanceled() public {
        // Create game but do NOT join it
        vm.prank(creator);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        // Cancel the game while still in WaitingForPlayer state
        vm.prank(creator);
        game.cancelGame(id);

        // Warp forward past timeoutPeriod to avoid TimeoutNotReached revert
        vm.warp(block.timestamp + game.timeoutPeriod() + 1);

        // Try to claim timeout win, should revert GameNotActive because state is Canceled
        vm.prank(creator);
        vm.expectRevert(TicTacToe.GameNotActive.selector);
        game.claimWinByTimeout(id);
    }

    function testCreateGame_RevertsIfInvalidBet() public {
        vm.deal(creator, 2 ether);
        vm.prank(creator);
        vm.expectRevert(TicTacToe.InvalidBet.selector);
        game.createGame{value: 0}(TicTacToe.Player.X);  // zero value, invalid bet

        vm.prank(creator);
        vm.expectRevert(TicTacToe.InvalidBet.selector);
        game.createGame{value: 2 ether}(TicTacToe.Player.X);  // too high, invalid bet
    }


    function testJoinGame_RevertsIfJoinOwnGame() public {
        // creator creates game with a valid bet
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        // creator tries to join their own game - must revert
        vm.deal(creator, 1 ether);
        vm.prank(creator);
        vm.expectRevert(TicTacToe.CannotJoinOwnGame.selector);
        game.joinGame{value: 0.1 ether}(id);
    }


    function testJoinGame_RevertsIfBetMismatch() public {
        uint id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(opponent);
        vm.expectRevert(TicTacToe.MustMatchBet.selector);
        game.joinGame{value: 0.2 ether}(id);
    }

    function testMakeMove_RevertsIfOutOfBounds() public {
        uint id = _createAndJoin();
        vm.prank(creator);
        vm.expectRevert(TicTacToe.OutOfBounds.selector);
        game.makeMove(id, 3, 0);
        vm.prank(creator);
        vm.expectRevert(TicTacToe.OutOfBounds.selector);
        game.makeMove(id, 0, 3);
    }

    function testCancelGame_Success() public {
        vm.prank(creator);
        uint id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.expectEmit(true, true, true, true);
        emit GameCanceled(id);

        vm.prank(creator);
        game.cancelGame(id);

        (, , , , , TicTacToe.GameState state, , ) = game.getGameMeta(id);
        assertEq(uint8(state), uint8(TicTacToe.GameState.Canceled));
    }



    function testSafeSend_TransferFails() public {
        // Already tested in testFinishGameWithWinner_SafeSendFails and testFinishGameWithDraw_SafeSendFails
        // But you can add an explicit call to withdrawDevFees from badDev to cover all transfer fails.
        uint id = _createAndWin(gameWithBadDev);
        console.log(id);
        vm.prank(address(badDev));
        vm.expectRevert(TicTacToe.TransferFailed.selector);
        gameWithBadDev.withdrawDevFees();
    }

    function testJoinGame_InvalidStatesAndInputs() public {
        // ──────── 1. GameDoesNotExist ────────
        vm.expectRevert(TicTacToe.GameDoesNotExist.selector);
        game.joinGame{value: 0.1 ether}(999);

        // ──────── 2. CannotJoinOwnGame ────────
        vm.prank(creator);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        vm.prank(creator);
        vm.expectRevert(TicTacToe.CannotJoinOwnGame.selector);
        game.joinGame{value: 0.1 ether}(id);

        // ──────── 3. MustMatchBet ────────
        vm.prank(opponent);
        vm.expectRevert(TicTacToe.MustMatchBet.selector);
        game.joinGame{value: 0.2 ether}(id); // too much

        vm.prank(opponent);
        vm.expectRevert(TicTacToe.MustMatchBet.selector);
        game.joinGame{value: 0.05 ether}(id); // too little

        // ──────── 4. Valid Join ────────
        vm.prank(opponent);
        game.joinGame{value: 0.1 ether}(id); // should succeed

        // ──────── 5. NotJoinable ────────
        vm.prank(outsider);
        vm.expectRevert(TicTacToe.NotJoinable.selector);
        game.joinGame{value: 0.1 ether}(id); // already joined
    }

    function testClaimAndCancel_InvalidBranches() public {
        // ───── Setup game 1 (joined) ─────
        vm.prank(creator);
        uint256 id = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);
        vm.prank(opponent);
        game.joinGame{value: 0.1 ether}(id);

        // ───── claimWinByTimeout: GameDoesNotExist ─────
        vm.expectRevert(TicTacToe.GameDoesNotExist.selector);
        game.claimWinByTimeout(999);

        // ───── claimWinByTimeout: TimeoutNotReached ─────
        vm.prank(creator);
        vm.expectRevert(TicTacToe.TimeoutNotReached.selector);
        game.claimWinByTimeout(id);

        // ───── Warp time to exceed first timeout window ─────
        vm.warp(block.timestamp + game.timeoutPeriod() + 1);

        // ───── claimWinByTimeout: NotAPlayer ─────
        vm.prank(outsider);
        vm.expectRevert(TicTacToe.NotAPlayer.selector);
        game.claimWinByTimeout(id);

        // ───── Setup game 2 (not joined) for GameNotActive check ─────
        vm.prank(creator);
        uint256 id2 = game.createGame{value: 0.1 ether}(TicTacToe.Player.X);

        // ───── claimWinByTimeout: GameNotActive (WaitingForPlayer) ─────
        vm.prank(creator);
        vm.expectRevert(TicTacToe.GameNotActive.selector);
        game.claimWinByTimeout(id2);

        // ───── Make moves to trigger YouMustMove ─────
        vm.prank(creator);  game.makeMove(id, 0, 0);
        vm.prank(opponent); game.makeMove(id, 1, 0);

        // It’s now creator’s turn.  Advance past the *new* timeout window
        // so the creator is late on their own move and we hit the branch.
        vm.warp(block.timestamp + game.timeoutPeriod() + 1);

        vm.prank(creator);
        vm.expectRevert(TicTacToe.YouMustMove.selector);
        game.claimWinByTimeout(id);

        // ───── cancelGame: GameDoesNotExist ─────
        vm.expectRevert(TicTacToe.GameDoesNotExist.selector);
        game.cancelGame(999);

        // ───── cancelGame: CannotCancel (already joined) ─────
        vm.prank(creator);
        vm.expectRevert(TicTacToe.CannotCancel.selector);
        game.cancelGame(id);

        // ───── cancelGame: NotAuthorized ─────
        vm.prank(opponent);
        vm.expectRevert(TicTacToe.NotAuthorized.selector);
        game.cancelGame(id2);
    }


}
