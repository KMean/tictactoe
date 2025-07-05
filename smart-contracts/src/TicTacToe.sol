// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TicTacToe is ReentrancyGuard {
    enum Player { None, X, O }
    enum GameState { WaitingForPlayer, InProgress, Finished, Canceled }

    uint256 public constant MIN_BET = 0.01 ether;
    uint256 public constant MAX_BET = 1 ether;
    uint256 public constant DEV_FEE_PERCENT = 2;
    uint256 public timeoutPeriod = 10 minutes;

    address public immutable devFeeReceiver;
    uint256 public gameCount;
    uint256 public accumulatedDevFees;

    struct Game {
        address payable creator;
        address payable opponent;
        Player creatorSymbol;
        Player turn;
        uint256 bet;
        GameState state;
        Player[3][3] board;
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

    // ────────────── Custom Errors ──────────────
    error InvalidBet();
    error InvalidSymbol();
    error NotJoinable();
    error CannotJoinOwnGame();
    error MustMatchBet();
    error GameNotActive();
    error OutOfBounds();
    error CellTaken();
    error NotYourTurn();
    error NotAPlayer();
    error TimeoutNotReached();
    error YouMustMove();
    error CannotCancel();
    error NotAuthorized();
    error TransferFailed();
    error GameDoesNotExist();

    // ────────────── Events ──────────────
    event GameCreated(uint256 indexed gameId, address creator, uint256 bet, Player symbol);
    event GameJoined(uint256 indexed gameId, address opponent);
    event MoveMade(uint256 indexed gameId, address player, uint8 x, uint8 y);
    event GameEnded(uint256 indexed gameId, address winner);
    event GameDraw(uint256 indexed gameId);
    event GameCanceled(uint256 indexed gameId);
    event WinByTimeout(uint256 indexed gameId, address winner);
    event DevFeesWithdrawn(uint256 amount);

    constructor(address _devFeeReceiver) {
        devFeeReceiver = _devFeeReceiver;
    }

    function createGame(Player _symbol) external payable returns (uint256) {
        if (msg.value < MIN_BET || msg.value > MAX_BET) revert InvalidBet();
        if (_symbol != Player.X && _symbol != Player.O) revert InvalidSymbol();

        uint256 gameId = gameCount++;
        Game storage g = games[gameId];
        g.creator = payable(msg.sender);
        g.creatorSymbol = _symbol;
        g.bet = msg.value;
        g.state = GameState.WaitingForPlayer;

        emit GameCreated(gameId, msg.sender, msg.value, _symbol);
        return gameId;
    }

    function joinGame(uint256 gameId) external payable {
        Game storage g = games[gameId];
        if (g.creator == address(0)) revert GameDoesNotExist();
        if (g.state != GameState.WaitingForPlayer) revert NotJoinable();
        if (msg.sender == g.creator) revert CannotJoinOwnGame();
        if (msg.value != g.bet) revert MustMatchBet();

        g.opponent = payable(msg.sender);
        g.state = GameState.InProgress;
        g.turn = Player.X;
        g.lastMoveTime = block.timestamp;

        emit GameJoined(gameId, msg.sender);
    }

    function makeMove(uint256 gameId, uint8 x, uint8 y) external nonReentrant {
        Game storage g = games[gameId];
        if (g.creator == address(0)) revert GameDoesNotExist();
        if (g.state != GameState.InProgress) revert GameNotActive();
        if (x >= 3 || y >= 3) revert OutOfBounds();
        if (g.board[x][y] != Player.None) revert CellTaken();

        Player currentSymbol = getPlayerSymbol(g, msg.sender);
        if (currentSymbol != g.turn) revert NotYourTurn();

        g.board[x][y] = currentSymbol;
        g.lastMoveTime = block.timestamp;

        emit MoveMade(gameId, msg.sender, x, y);

        if (checkWin(g.board, currentSymbol)) {
            g.state = GameState.Finished;
            g.winner = payable(msg.sender);

            uint256 fee = (2 * g.bet * DEV_FEE_PERCENT) / 100;
            uint256 payout = 2 * g.bet - fee;

            _safeSend(g.winner, payout);
            accumulatedDevFees += fee;

            leaderboard[msg.sender].wins += 1;
            address loser = msg.sender == g.creator ? g.opponent : g.creator;
            leaderboard[loser].losses += 1;

            emit GameEnded(gameId, msg.sender);
        } else if (isDraw(g.board)) {
            g.state = GameState.Finished;
            _safeSend(g.creator, g.bet);
            _safeSend(g.opponent, g.bet);

            leaderboard[g.creator].draws += 1;
            leaderboard[g.opponent].draws += 1;

            emit GameDraw(gameId);
        } else {
            g.turn = (g.turn == Player.X) ? Player.O : Player.X;
        }
    }

    function claimWinByTimeout(uint256 gameId) external nonReentrant {
        Game storage g = games[gameId];
        if (g.creator == address(0)) revert GameDoesNotExist();
        if (g.state != GameState.InProgress) revert GameNotActive();
        if (block.timestamp <= g.lastMoveTime + timeoutPeriod) revert TimeoutNotReached();

        Player currentTurn = g.turn;
        address payable expectedPlayer = (currentTurn == g.creatorSymbol)
            ? g.creator
            : g.opponent;

        if (msg.sender == expectedPlayer) revert YouMustMove();

        g.state = GameState.Finished;
        g.winner = payable(msg.sender);

        uint256 fee = (2 * g.bet * DEV_FEE_PERCENT) / 100;
        uint256 payout = 2 * g.bet - fee;

        _safeSend(payable(msg.sender), payout);
        accumulatedDevFees += fee;

        leaderboard[msg.sender].wins += 1;
        address loser = msg.sender == g.creator ? g.opponent : g.creator;
        leaderboard[loser].losses += 1;

        emit WinByTimeout(gameId, msg.sender);
    }

    function cancelGame(uint256 gameId) external nonReentrant {
        Game storage g = games[gameId];
        if (g.creator == address(0)) revert GameDoesNotExist();
        if (g.state != GameState.WaitingForPlayer) revert CannotCancel();
        if (msg.sender != g.creator) revert NotAuthorized();

        g.state = GameState.Canceled;
        _safeSend(g.creator, g.bet);

        emit GameCanceled(gameId);
    }

    function getPlayerSymbol(Game storage g, address player) internal view returns (Player) {
        if (player == g.creator) return g.creatorSymbol;
        if (player == g.opponent) return (g.creatorSymbol == Player.X) ? Player.O : Player.X;
        revert NotAPlayer();
    }

    function checkWin(Player[3][3] memory b, Player p) internal pure returns (bool) {
        for (uint8 i = 0; i < 3; i++) {
            if (
                (b[i][0] == p && b[i][1] == p && b[i][2] == p) ||
                (b[0][i] == p && b[1][i] == p && b[2][i] == p)
            ) return true;
        }
        return (b[0][0] == p && b[1][1] == p && b[2][2] == p) ||
               (b[0][2] == p && b[1][1] == p && b[2][0] == p);
    }

    function isDraw(Player[3][3] memory b) internal pure returns (bool) {
        for (uint8 i = 0; i < 3; i++)
            for (uint8 j = 0; j < 3; j++)
                if (b[i][j] == Player.None)
                    return false;
        return true;
    }

    function _safeSend(address payable to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    function withdrawFees() external nonReentrant {
        if (msg.sender != devFeeReceiver) revert NotAuthorized();
        uint256 amount = accumulatedDevFees;
        accumulatedDevFees = 0;
        _safeSend(payable(devFeeReceiver), amount);
        emit DevFeesWithdrawn(amount);
    }

    function setTimeoutPeriod(uint256 _seconds) external {
        if (msg.sender != devFeeReceiver) revert NotAuthorized();
        timeoutPeriod = _seconds;
    }

    function getBoard(uint256 gameId) external view returns (Player[3][3] memory) {
        if (games[gameId].creator == address(0)) revert GameDoesNotExist();
        return games[gameId].board;
    }

    function getLeaderboard(address player) external view returns (Stats memory) {
        return leaderboard[player];
    }
}
