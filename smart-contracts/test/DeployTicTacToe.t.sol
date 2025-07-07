// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {DeployTicTacToe} from "../script/DeployTicTacToe.s.sol";
import {TicTacToe}      from "../src/TicTacToe.sol";

contract DeployTicTacToeTest is Test {
    /// @notice Ensures the deploy script works and configures the contract correctly.
    function testDeployScriptSetsCorrectReceiver() public {
        // ─── Act ────────────────────────────────────────────────────────────────
        DeployTicTacToe deployScript = new DeployTicTacToe();
        TicTacToe game = deployScript.run();

        // ─── Assert ─────────────────────────────────────────────────────────────
        // 1. Contract really exists
        assertTrue(address(game) != address(0), "Deployment returned zero address");
        assertGt(address(game).code.length, 0, "No code at deployed address");

        // 2. devFeeReceiver was wired up exactly as in the script
        address expectedReceiver = 0xc6CD8842EB67684a763Fe776843f693bB3e48850;
        assertEq(game.devFeeReceiver(), expectedReceiver, "devFeeReceiver mismatch");

        // 3. Optional sanity: default timeout should be 10 minutes
        assertEq(game.timeoutPeriod(), 10 minutes, "unexpected default timeout");
    }
}
