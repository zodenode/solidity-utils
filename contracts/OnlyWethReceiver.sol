/**
 * @title OnlyWethReceiver
 * @dev Abstract contract that extends the EthReceiver contract and only allows receiving ETH from a specific contract
 */
 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EthReceiver.sol";

abstract contract OnlyWethReceiver is EthReceiver {
    address private immutable _WETH; // solhint-disable-line var-name-mixedcase

    /**
     * @dev Constructor that sets the address of the WETH contract
     * @param weth The address of the WETH contract
     */
    constructor(address weth) {
        _WETH = address(weth);
    }

    /**
     * @dev Overrides the receive function of the EthReceiver contract to only allow receiving ETH from the WETH contract
     */
    function _receive() internal virtual override {
        if (msg.sender != _WETH) revert EthDepositRejected();
    }
}
