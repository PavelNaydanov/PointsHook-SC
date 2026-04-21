// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {PointsHook} from "../src/PointsHook.sol";

contract DeployHook is Script {
    function run(IPoolManager poolManager) external {
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);

        bytes memory constructorArgs = abi.encode(poolManager);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_FACTORY, flags, type(PointsHook).creationCode, constructorArgs);

        vm.startBroadcast();
        PointsHook hook = new PointsHook{salt: salt}(poolManager);
        vm.stopBroadcast();

        require(address(hook) == hookAddress, "DeployHookScript: Hook Address Mismatch");

        console.log("Hook deployed at:", address(hook));
    }
}