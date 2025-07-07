// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TicTacToe} from "../src/TicTacToe.sol";

contract DeployTicTacToe is Script {
    function run() external returns (TicTacToe) {
        address devFeeReceiver = 0xc6CD8842EB67684a763Fe776843f693bB3e48850;
        vm.startBroadcast();
        TicTacToe ticTacToe = new TicTacToe(devFeeReceiver);
        vm.stopBroadcast();
        return ticTacToe;
    }
}
