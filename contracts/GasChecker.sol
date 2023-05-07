/**
 * @title GasChecker
 * @dev A contract that allows to check the gas cost of a function call
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GasChecker {
    /**
     * @dev Emitted when the actual gas cost is different than the expected one
     * @param expected Expected gas cost
     * @param actual Actual gas cost
     */
    error GasCostDiffers(uint256 expected, uint256 actual);

    /**
     * @dev Modifier that checks the gas cost of a function call
     * @param expected Expected gas cost
     */
    modifier checkGasCost(uint256 expected) {
        uint256 gas = gasleft(); // Get the gas remaining at the beginning of the function call
        _;
        unchecked {
            gas -= gasleft(); // Calculate the actual gas cost by subtracting the remaining gas at the end of the function call from the initial gas
        }
        if (expected > 0 && gas != expected) { // If an expected gas cost is specified and it is not equal to the actual gas cost, revert
            revert GasCostDiffers(expected, gas);
        }
    }
}
