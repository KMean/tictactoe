// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title TicTacToe
 * @author Kim Ranzani
 * @notice On-chain 3×3 Tic-Tac-Toe with wagers, timeout, and leaderboard.
 *         * 2% dev fee on decisive wins (draws refund 100%).
 *         * X always starts; creator chooses their symbol.
 *         * Gas-optimized using bitmap logic for win checks.
 */
contract TicTacToe is ReentrancyGuard {
    enum Player { None, X, O }
    enum GameState { WaitingForPlayer, InProgress, Finished, Canceled }

    uint256 public constant MIN_BET = 0.01 ether;
    uint256 public constant MAX_BET = 1 ether;
    uint256 public constant DEV_FEE_PERCENT = 2;

    uint256 public timeoutPeriod = 10 minutes;
    address immutable public devFeeReceiver;

    uint256 public gameCount;
    uint256 public accumulatedDevFees;

    struct Game {
        address payable creator;
        address payable opponent;
        Player creatorSymbol;
        Player turn;
        uint256 bet;
        GameState state;
        uint256 boardX;
        uint256 boardO;
        address payable winner;
        uint256 lastMoveTime;
    }

    struct Stats {
        uint256 wins;
        uint256 losses;
        uint256 draws;
    }

    mapping(uint256 => Game) public games;
    mapping(address => Stats) public leaderboard;

    uint256[8] internal WINNING_MASKS;

    error InvalidBet(); error InvalidSymbol(); error NotJoinable();
    error CannotJoinOwnGame(); error MustMatchBet(); error GameNotActive();
    error OutOfBounds(); error CellTaken(); error NotYourTurn();
    error NotAPlayer(); error TimeoutNotReached(); error YouMustMove();
    error CannotCancel(); error NotAuthorized(); error TransferFailed();
    error GameDoesNotExist();

    event GameCreated(uint256 indexed id, address creator, uint256 bet, Player symbol);
    event GameJoined(uint256 indexed id, address opponent);
    event MoveMade(uint256 indexed id, address player, uint8 x, uint8 y);
    event GameEnded(uint256 indexed id, address winner);
    event WinByTimeout(uint256 indexed id, address winner);
    event GameDraw(uint256 indexed id);
    event GameCanceled(uint256 indexed id);
    event DevFeesWithdrawn(uint256 amount);

    constructor(address _devFeeReceiver) {
        devFeeReceiver = _devFeeReceiver;
        WINNING_MASKS = [
            0x7, 0x38, 0x1C0, // Rows
            0x49, 0x92, 0x124, // Columns
            0x111, 0x54        // Diagonals
        ];
    }

    function createGame(Player _symbol) external payable returns (uint256 id) {
        if (msg.value < MIN_BET || msg.value > MAX_BET) revert InvalidBet();
        if (_symbol != Player.X && _symbol != Player.O) revert InvalidSymbol();
        id = gameCount++;
        Game storage g = games[id];
        g.creator = payable(msg.sender);
        g.creatorSymbol = _symbol;
        g.bet = msg.value;
        g.state = GameState.WaitingForPlayer;
        emit GameCreated(id, msg.sender, msg.value, _symbol);
    }

    function joinGame(uint256 id) external payable nonReentrant {
        Game storage g = games[id];
        if (g.creator == address(0)) revert GameDoesNotExist();
        if (g.state != GameState.WaitingForPlayer) revert NotJoinable();
        if (msg.sender == g.creator) revert CannotJoinOwnGame();
        if (msg.value != g.bet) revert MustMatchBet();
        g.opponent = payable(msg.sender);
        g.state = GameState.InProgress;
        g.turn = Player.X;
        g.lastMoveTime = block.timestamp;
        emit GameJoined(id, msg.sender);
    }

    function makeMove(uint256 id, uint8 x, uint8 y) external nonReentrant {
        if (x > 2 || y > 2) revert OutOfBounds();
        Game storage g = games[id];
        if (g.creator == address(0)) revert GameDoesNotExist();
        if (g.state != GameState.InProgress) revert GameNotActive();

        uint8 pos = y * 3 + x;
        uint256 mask = 1 << pos;
        Player p = _playerSymbol(g, msg.sender);

        if (p != g.turn) revert NotYourTurn();
        if ((g.boardX | g.boardO) & mask != 0) revert CellTaken();

        if (p == Player.X) g.boardX |= mask;
        else g.boardO |= mask;

        g.lastMoveTime = block.timestamp;
        emit MoveMade(id, msg.sender, x, y);

        uint256 board = p == Player.X ? g.boardX : g.boardO;
        if (_isWin(board)) {
            _finishGameWithWinner(g, id, msg.sender);
        } else if ((g.boardX | g.boardO) == 511) {
            _finishGameWithDraw(g, id);
        } else {
            g.turn = p == Player.X ? Player.O : Player.X;
        }
    }

    function claimWinByTimeout(uint256 id) external nonReentrant {
        Game storage g = games[id];
        if (g.creator == address(0)) revert GameDoesNotExist();
        if (block.timestamp <= g.lastMoveTime + timeoutPeriod) revert TimeoutNotReached();
        if (msg.sender != g.creator && msg.sender != g.opponent) revert NotAPlayer();
        if (g.state != GameState.InProgress || g.opponent == address(0)) revert GameNotActive();

        address payable expected = (g.turn == g.creatorSymbol) ? g.creator : g.opponent;
        if (msg.sender == expected) revert YouMustMove();

        _finishGameWithWinner(g, id, msg.sender);
        emit WinByTimeout(id, msg.sender);
    }

    function cancelGame(uint256 id) external nonReentrant {
        Game storage g = games[id];
        if (g.creator == address(0)) revert GameDoesNotExist();

        // Check if game is cancelable first:
        if (g.state != GameState.WaitingForPlayer) revert CannotCancel();

        // Then check if caller is authorized:
        if (msg.sender != g.creator) revert NotAuthorized();

        g.state = GameState.Canceled;
        _safeSend(g.creator, g.bet);
        emit GameCanceled(id);
    }



    function withdrawDevFees() external {
        if (msg.sender != devFeeReceiver) revert NotAuthorized();
        uint256 amount = accumulatedDevFees;
        accumulatedDevFees = 0;
        _safeSend(payable(devFeeReceiver), amount);
        emit DevFeesWithdrawn(amount);
    }

    function getGameState(uint256 id) external view returns (Game memory) {
        if (games[id].creator == address(0)) revert GameDoesNotExist();
        return games[id];
    }

    function getSecondsUntilTimeout(uint256 id) external view returns (uint256) {
        Game storage g = games[id];
        if (g.creator == address(0)) revert GameDoesNotExist();
        if (g.state != GameState.InProgress) return 0;
        uint256 end = g.lastMoveTime + timeoutPeriod;
        return block.timestamp >= end ? 0 : end - block.timestamp;
    }

    function isPlayer(uint256 id, address a) external view returns (bool) {
        Game storage g = games[id];
        if (g.creator == address(0)) revert GameDoesNotExist();
        return a == g.creator || a == g.opponent;
    }

    function getLeaderboard(address a) external view returns (Stats memory) {
        return leaderboard[a];
    }

    function getGameMeta(uint256 id) external view returns (
        address creator,
        address opponent,
        Player creatorSymbol,
        Player turn,
        uint256 bet,
        GameState state,
        address winner,
        uint256 lastMoveTime
    ) {
        Game storage g = games[id];
        if (g.creator == address(0)) revert GameDoesNotExist();
        return (g.creator, g.opponent, g.creatorSymbol, g.turn, g.bet, g.state, g.winner, g.lastMoveTime);
    }

    function getBoardState(uint256 id) external view returns (Player[9] memory board) {
        Game storage g = games[id];
        if (g.creator == address(0)) revert GameDoesNotExist();
        for (uint8 i = 0; i < 9; ++i) {
            if ((g.boardX >> i) & 1 == 1) {
                board[i] = Player.X;
            } else if ((g.boardO >> i) & 1 == 1) {
                board[i] = Player.O;
            } else {
                board[i] = Player.None;
            }
        }
    }

    function _playerSymbol(Game storage g, address who) private view returns (Player) {
        if (who == g.creator) return g.creatorSymbol;
        if (who == g.opponent) return g.creatorSymbol == Player.X ? Player.O : Player.X;
        revert NotAPlayer();
    }

    function _isWin(uint256 b) private view returns (bool) {
        for (uint8 i = 0; i < 8; ++i)
            if ((b & WINNING_MASKS[i]) == WINNING_MASKS[i])
                return true;
        return false;
    }

    function _finishGameWithWinner(Game storage g, uint256 id, address winner) private {
        g.state = GameState.Finished;
        g.winner = payable(winner);

        leaderboard[winner].wins++;
        address loser = winner == g.creator ? g.opponent : g.creator;
        leaderboard[loser].losses++;

        uint256 totalPot = 2 * g.bet;
        uint256 fee = (totalPot * DEV_FEE_PERCENT) / 100;
        uint256 payout = totalPot - fee;
        accumulatedDevFees += fee;

        _safeSend(payable(winner), payout);            
              
        emit GameEnded(id, winner);                    
    }

    function _finishGameWithDraw(Game storage g, uint256 id) private {
        g.state = GameState.Finished;
        leaderboard[g.creator].draws++;
        leaderboard[g.opponent].draws++;
        emit GameDraw(id);
        _safeSend(g.creator, g.bet);
        _safeSend(g.opponent, g.bet);
    }

    function _safeSend(address payable to, uint256 amt) private {
        (bool ok, ) = to.call{value: amt}("");
        if (!ok) revert TransferFailed();
    }

    function setTimeoutPeriod(uint256 newTimeout) external {
        if (msg.sender != devFeeReceiver) revert NotAuthorized();
        timeoutPeriod = newTimeout;
    }
}
