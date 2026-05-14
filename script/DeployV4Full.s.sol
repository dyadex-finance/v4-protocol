// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";

import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {PositionDescriptor} from "@uniswap/v4-periphery/src/PositionDescriptor.sol";
import {PositionManager} from "@uniswap/v4-periphery/src/PositionManager.sol";
import {IPositionDescriptor} from "@uniswap/v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {V4Quoter} from "@uniswap/v4-periphery/src/lens/V4Quoter.sol";
import {StateView} from "@uniswap/v4-periphery/src/lens/StateView.sol";

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";

/// @notice Deploy the full Uniswap V4 protocol stack to a new EVM chain.
///
/// Configure the constants below, then run:
///
///   forge script script/DeployV4Full.s.sol \
///     --rpc-url <RPC_URL> \
///     --broadcast \
///     --verify \
///     --etherscan-api-key <KEY>
///
/// For chains without a pre-deployed Permit2, set PERMIT2_CANONICAL to address(0)
/// and the script will deploy a fresh instance.
contract DeployV4Full is Script {
    // =========================================================================
    // Configure these before deploying
    // =========================================================================

    /// @dev Deployer / initial protocol fee controller.
    ///      Leave address(0) to use msg.sender (the broadcast key).
    address constant DEPLOYER = address(0);

    /// @dev Wrapped native token on the target chain (e.g. WETH, WMATIC, WBNB).
    ///      Read from the WETH9 environment variable at runtime.
    address weth9;

    /// @dev Human-readable label for the native currency (padded to bytes32).
    string constant NATIVE_LABEL = "MON";

    /// @dev Canonical Permit2 address. The script reuses it when already deployed.
    ///      Set to address(0) to always deploy a fresh Permit2.
    address constant PERMIT2_CANONICAL = 0x000000000022D473030F116DFC393057b8271978;

    // ---- V2 / V3 parameters ------------------------------------------------

    address constant V2_FACTORY = address(0);
    address constant V3_FACTORY = address(0);
    bytes32 constant V2_PAIR_INIT_CODE_HASH = bytes32(0);
    bytes32 constant V3_POOL_INIT_CODE_HASH = bytes32(0);

    // ---- Universal Router extra parameters --------------------------------

    // =========================================================================
    // Deployment state (populated by run())
    // =========================================================================

    address public permit2;
    PoolManager public poolManager;
    PositionDescriptor public positionDescriptor;
    PositionManager public positionManager;
    V4Quoter public quoter;
    StateView public stateView;

    function run() external {
        weth9 = vm.envAddress("WETH9");
        require(weth9 != address(0), "DeployV4Full: set WETH9 before deploying");

        address deployer = DEPLOYER == address(0) ? msg.sender : DEPLOYER;

        vm.startBroadcast();

        // ---------------------------------------------------------------------
        // 1. Permit2
        // ---------------------------------------------------------------------
        if (PERMIT2_CANONICAL != address(0) && PERMIT2_CANONICAL.code.length > 0) {
            permit2 = PERMIT2_CANONICAL;
            console2.log("Permit2 (existing)   :", permit2);
        } else {
            permit2 = address(new DeployPermit2().deployPermit2());
            console2.log("Permit2 (deployed)   :", permit2);
        }

        // ---------------------------------------------------------------------
        // 2. PoolManager
        // ---------------------------------------------------------------------
        poolManager = new PoolManager(deployer);
        console2.log("PoolManager          :", address(poolManager));

        // ---------------------------------------------------------------------
        // 3. PositionDescriptor
        // ---------------------------------------------------------------------
        bytes32 nativeLabelBytes = _toBytes32(NATIVE_LABEL);
        positionDescriptor = new PositionDescriptor(
            IPoolManager(address(poolManager)),
            weth9,
            nativeLabelBytes
        );
        console2.log("PositionDescriptor   :", address(positionDescriptor));

        // ---------------------------------------------------------------------
        // 4. PositionManager
        //    unsubscribeGasLimit of 300_000 matches the canonical mainnet value.
        // ---------------------------------------------------------------------
        positionManager = new PositionManager(
            IPoolManager(address(poolManager)),
            IAllowanceTransfer(permit2),
            300_000,
            IPositionDescriptor(address(positionDescriptor)),
            IWETH9(weth9)
        );
        console2.log("PositionManager      :", address(positionManager));

        // ---------------------------------------------------------------------
        // 5. Quoter (V4Quoter)
        // ---------------------------------------------------------------------
        quoter = new V4Quoter(IPoolManager(address(poolManager)));
        console2.log("Quoter               :", address(quoter));

        // ---------------------------------------------------------------------
        // 6. StateView
        // ---------------------------------------------------------------------
        stateView = new StateView(IPoolManager(address(poolManager)));
        console2.log("StateView            :", address(stateView));

        vm.stopBroadcast();

        // Summary
        console2.log("\n=== Deployment Summary ===");
        console2.log("Chain ID             :", block.chainid);
        console2.log("Deployer             :", deployer);
        console2.log("Permit2              :", permit2);
        console2.log("PoolManager          :", address(poolManager));
        console2.log("PositionDescriptor   :", address(positionDescriptor));
        console2.log("PositionManager      :", address(positionManager));
        console2.log("Quoter               :", address(quoter));
        console2.log("StateView            :", address(stateView));
    }

    function _toBytes32(string memory s) internal pure returns (bytes32 result) {
        bytes memory b = bytes(s);
        require(b.length <= 32, "DeployV4Full: native label too long");
        assembly {
            result := mload(add(b, 32))
        }
    }
}
