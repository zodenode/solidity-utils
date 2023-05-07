/**
 * @title EthReceiver
 * @dev A contract that can receive Ether deposits and reject them if they were not sent from a contract account
 */
 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract EthReceiver {
    
    /**
     * @dev Emitted when a deposit is rejected because it was not sent from a contract account
     */
    error EthDepositRejected();
    
    /**
     * @dev Fallback function that is called when a contract receives Ether
     */
    receive() external payable {
        _receive();
    }

    /**
     * @dev Internal function to receive Ether deposits and reject them if they were not sent from a contract account
     */
    function _receive() internal virtual {
        if (msg.sender == tx.origin) revert EthDepositRejected();
    }
}
