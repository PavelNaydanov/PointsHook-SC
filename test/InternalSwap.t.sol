// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {InternalSwapPool} from "../src/InternalSwapPool.sol";

contract InternalSwapPoolTest is Test, Deployers {
    InternalSwapPool hook;

    function setUp() public {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        // InternalSwapPool flags: beforeAddLiquidity | beforeRemoveLiquidity | beforeSwap | afterSwap | beforeSwapReturnDelta | afterSwapReturnDelta
        uint160 flags = uint160(
            Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
            Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG |
            Hooks.BEFORE_SWAP_FLAG |
            Hooks.AFTER_SWAP_FLAG |
            Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
            Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        deployCodeTo(
            "InternalSwapPool.sol",
            abi.encode(manager, Currency.unwrap(currency0)),
            address(flags)
        );
        hook = InternalSwapPool(address(flags));

        (key,) = initPool(currency0, currency1, hook, 3000, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1000 ether,
                salt: bytes32(0)
            }),
            ZERO_BYTES
        );
    }

    /**
     * Swap that does NOT hit the internal swap path.
     * - Internal swap only runs when zeroForOne && _poolFees[poolId].amount1 != 0.
     * - Do a oneForZero swap (sell token1 for token0). Fees accumulate in amount0 only;
     *   amount1 stays 0. So the next zeroForOne swap would go entirely through the pool.
     */
    function test_swap_doesNotHitInternalSwap() public {
        // oneForZero: user sells token1 for token0. Hook takes 1% fee in token0 (amount0).
        swap(key, false, -1 ether, ZERO_BYTES);

        InternalSwapPool.ClaimableFees memory fees = hook.poolFees(key);
        assertEq(fees.amount1, 0, "hook has no token1 fees after oneForZero");
        assertGt(fees.amount0, 0, "hook has token0 fees");
        // So a zeroForOne swap in this state would NOT use internal fill (amount1 == 0).
    }

    /**
     * Swap that DOES hit the internal swap path.
     * - Do a zeroForOne swap (sell token0 for token1). Hook takes 1% fee in token1 (amount1 > 0).
     * - So the next zeroForOne swap would trigger the internal path in beforeSwap, filling
     *   (partially or fully) from the hook's token1 fees instead of the pool.
     */
    function test_swap_hitsInternalSwap() public {
        // zeroForOne: user sells token0 for token1. Hook takes 1% fee in token1 (amount1).
        swap(key, true, -10 ether, ZERO_BYTES);

        InternalSwapPool.ClaimableFees memory fees = hook.poolFees(key);
        assertGt(fees.amount1, 0, "hook has token1 fees after zeroForOne");
        // So a zeroForOne swap in this state WOULD use internal fill (amount1 != 0).
    }
}